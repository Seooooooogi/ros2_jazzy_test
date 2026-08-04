#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# setup-app.sh — base 호스트 설치(install.sh) 위에 cobot2 애플리케이션 계층을 올린다.
#
#   workspace : cobot2 소스 확인 → m0609 bringup + onrobot → doosan-robot2 드라이버 + DSR 의존성 →
#               RealSense SDK / ROS2 wrapper → host voice Python → colcon build.
#   containers: nvidia-container-toolkit → yolo 이미지(:dev-builder — 소스를 live-mount 하는 개발용).
#
# install.sh 와 그 재부팅이 끝난 뒤에 실행한다.
# 콘솔에는 [n/total] 배너와 heartbeat 만 보이고 apt / colcon / docker 의 상세 출력은 install_log 로
# 간다(--verbose 면 콘솔에도 함께). sudo 프롬프트는 /dev/tty 로 가서 로그 라우팅에 삼켜지지 않는다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="${SCRIPT_DIR}/resources"

# shellcheck source=resources/config.sh
source "${RESOURCE_DIR}/config.sh"
# shellcheck source=resources/lib.sh
source "${RESOURCE_DIR}/lib.sh"   # sudo_prime 제공
config_assert_set

LOG="${LOG_FILE}"
mkdir -p "$(dirname "${LOG}")"
VERBOSE="${VERBOSE:-0}"

DO_WORKSPACE=1
DO_CONTAINERS=1
RESET=0
ASSUME_YES=0

usage() {
    cat <<EOF
setup-app.sh — set up the cobot2 application (workspace + containers) on top of the base install.sh.

  bash setup-app.sh                 workspace (driver + cobot2 + m0609 bringup + RealSense + host voice + colcon) + containers (toolkit + yolo :dev-builder image)
  bash setup-app.sh --workspace-only   only the workspace (incl. host voice Python)
  bash setup-app.sh --containers-only  only the container layer (toolkit + yolo image)
  bash setup-app.sh --reset         wipe the doosan-robot2 clone + build/install/log first, then rebuild
                                    (cobot2 source is NOT touched). Asks to confirm unless --yes.
  bash setup-app.sh --verbose       also stream each step's detailed output to the console (default: only install_log).
  bash setup-app.sh -y, --yes       skip the --reset confirmation (non-interactive).
  bash setup-app.sh -h, --help      this help.

The cobot2 application source is NOT shipped by this repo — place it at ${DSR_WORKSPACE}/src/cobot2 before running.
The m0609 bringup repo is cloned to ${M0609_REPO_DIR} when missing (override M0609_REPO_DIR / M0609_REF),
and only its m0609_rg2_bringup package is symlinked into ${DSR_WORKSPACE}/src.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose)      VERBOSE=1 ;;
        --workspace-only)  DO_CONTAINERS=0 ;;
        --containers-only) DO_WORKSPACE=0 ;;
        --reset)           RESET=1 ;;
        -y|--yes)          ASSUME_YES=1 ;;
        -h|--help)         usage; exit 0 ;;
        *) echo "[setup-app] unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if [[ ${DO_WORKSPACE} -eq 0 && ${DO_CONTAINERS} -eq 0 ]]; then
    echo "[setup-app] --workspace-only and --containers-only are mutually exclusive." >&2
    exit 2
fi

# 실제 실행일 때만 배너(--help 는 이미 exit 했다).
print_copyright

# 진행률 분모 — [n/total] 표시에만 사용.
TOTAL=0
[[ ${DO_WORKSPACE} -eq 1 ]] && TOTAL=$(( TOTAL + 7 ))   # 7개: cobot2 확인 + m0609/onrobot + dsr + rs-sdk + rs-ros + voice-host + colcon
[[ ${DO_CONTAINERS} -eq 1 ]] && TOTAL=$(( TOTAL + 2 ))  # 2개: toolkit + yolo image

# 컨테이너만 돌 때는 워크스페이스 7단계가 빠지므로 번호를 앞으로 당긴다.
STEP_OFF=0
[[ ${DO_WORKSPACE} -eq 1 ]] || STEP_OFF=-7

# setup-app 은 재개 개념이 없다 — 단계 결과를 state 에 남기지 않고 배너와 로그만 쓴다.
STEP_STATE=0
STEPS_TOTAL="${TOTAL}"
LOG_FILE="${LOG}"

# cobot2 소스가 ${DSR_WORKSPACE}/src/cobot2 에 있는지 확인한다. 지금 정책은 사용자가 직접 배치하는
# 것이라 존재만 보고, 없으면 반쪽짜리 워크스페이스를 만들어 런타임에서 깨지게 두는 대신 여기서 멈춘다.
# 취득 방식을 git clone 등으로 바꿀 때 고칠 곳이 이 함수 하나가 되도록 격리해 두었다.
obtain_cobot2() {
    local cobot2="${DSR_WORKSPACE}/src/cobot2"
    if [[ -d "${cobot2}" ]] && find "${cobot2}" -name package.xml -print -quit | grep -q .; then
        echo "setup-app: cobot2 source found at ${cobot2}"
        return 0
    fi
    echo "setup-app: cobot2 application source not found at ${cobot2}" >&2
    echo "           This repo no longer ships cobot2 — place the source there, then re-run:" >&2
    echo "             mkdir -p ${DSR_WORKSPACE}/src && cp -a <cobot2-source> ${cobot2}" >&2
    echo "           Then split the monolithic lab packages out (README step 3-1):" >&2
    echo "             mkdir -p ${HOME}/cobot_venv_ws/src" >&2
    echo "             mv ${cobot2}/pick_and_place_{text,voice} ${HOME}/cobot_venv_ws/src/" >&2
    echo "             rm -f ${HOME}/cobot_venv_ws/src/pick_and_place_*/COLCON_IGNORE" >&2
    exit 1
}

# 통합 bringup(m0609_rg2_bringup)과 그 외부 의존(onrobot-ros2)을 워크스페이스에 준비한다.
#
# M0609 레포는 없을 때만 clone 한다 — 이미 있으면 개발 중인 작업본일 수 있어 건드리지 않는다.
# 워크스페이스에는 레포 전체가 아니라 bringup 패키지 하나만 심볼릭 링크한다. 같은 레포의
# m0609_rg2_moveit 은 rosdep 으로 moveit 스택을 통째로 끌어오는데 이 설치에서는 쓰지 않기 때문이고,
# colcon 이 심볼릭 링크된 패키지 디렉토리를 그대로 인식하는 것은 실측으로 확인했다.
# onrobot-ros2 는 M0609 레포가 추적하지 않는 외부 패키지라 커밋 SHA 로 핀 고정해 따로 clone 한다.
obtain_m0609() {
    local ws_src="${DSR_WORKSPACE}/src"
    local link="${ws_src}/m0609_rg2_bringup"
    local pkg="${M0609_REPO_DIR}/src/m0609_rg2_bringup"
    local onrobot="${ws_src}/onrobot-ros2"

    mkdir -p "${ws_src}"

    if [[ -d "${M0609_REPO_DIR}/.git" ]]; then
        echo "setup-app: m0609 repo already at ${M0609_REPO_DIR} (skip clone, M0609_REF ignored)"
    else
        git clone --branch "${M0609_REF}" "${M0609_REPO_URL}" "${M0609_REPO_DIR}"
    fi

    if [[ ! -f "${pkg}/package.xml" ]]; then
        echo "setup-app: ${pkg}/package.xml not found — check ${M0609_REPO_DIR}" >&2
        exit 1
    fi

    # 링크 자리에 실제 디렉토리가 있으면 ln -sfn 이 그 안쪽에 링크를 만들어 조용히 어긋난다.
    # 사용자가 손으로 복사해 둔 경우일 수 있으니 지우지 말고 멈춘다.
    if [[ -e "${link}" && ! -L "${link}" ]]; then
        echo "setup-app: ${link} exists and is not a symlink — remove it and re-run." >&2
        exit 1
    fi
    ln -sfn "${pkg}" "${link}"
    echo "setup-app: linked ${link} -> ${pkg}"

    if [[ -d "${onrobot}/.git" ]]; then
        echo "setup-app: onrobot-ros2 already cloned (skip)"
    else
        git clone "${ONROBOT_REPO_URL}" "${onrobot}"
    fi
    # clone 을 건너뛴 경우에도 핀을 다시 적용 — 누가 브랜치를 옮겨 놨어도 같은 커밋으로 수렴.
    git -C "${onrobot}" checkout --quiet "${ONROBOT_COMMIT}"
    echo "setup-app: onrobot-ros2 pinned at ${ONROBOT_COMMIT}"
}

# doosan-robot2 clone 과 build/install/log 를 지워 처음부터 다시 만들 준비를 한다. 다시 받거나
# 빌드하면 복구되는 것만 지우고, 사용자가 직접 둔 cobot2 소스는 건드리지 않는다.
# --yes 가 없으면 먼저 확인을 받고, 물어볼 TTY 가 없으면 그냥 종료한다.
do_reset() {
    if [[ ${ASSUME_YES} -ne 1 ]]; then
        if [[ -t 0 ]]; then
            read -r -p "[setup-app] --reset will rm -rf ${DSR_WORKSPACE}/src/{doosan-robot2,onrobot-ros2,m0609_rg2_bringup} and ${DSR_WORKSPACE}/{build,install,log} (cobot2 and ${M0609_REPO_DIR} kept). Continue? [y/N] " reply
            [[ "${reply}" =~ ^[Yy]$ ]] || { echo "[setup-app] aborted."; exit 1; }
        else
            echo "[setup-app] --reset needs confirmation but no TTY — re-run with --yes." >&2
            exit 1
        fi
    fi
    # m0609_rg2_bringup 은 심볼릭 링크라 지워도 원본(${M0609_REPO_DIR})은 그대로다.
    # onrobot-ros2 는 핀 고정 clone 이라 다시 받으면 같은 커밋으로 복구된다.
    echo "[setup-app] reset: wiping doosan-robot2 / onrobot-ros2 / m0609 link + build/install/log (cobot2 and ${M0609_REPO_DIR} kept)"
    rm -rf "${DSR_WORKSPACE}/src/doosan-robot2" \
           "${DSR_WORKSPACE}/src/onrobot-ros2" \
           "${DSR_WORKSPACE}/build" "${DSR_WORKSPACE}/install" "${DSR_WORKSPACE}/log"
    rm -f  "${DSR_WORKSPACE}/src/m0609_rg2_bringup"
}

do_workspace() {
    # 앞의 두 단계는 금방 끝나는 확인이라 run_step 대신 step_begin/step_end 로 — 출력을 로그로
    # 돌리지 않고 콘솔에 그대로 보여 준다.
    step_begin 1 "${TOTAL}" "cobot2 source (verify)"; obtain_cobot2; step_end DONE
    step_begin 2 "${TOTAL}" "m0609 bringup + onrobot-ros2"; obtain_m0609; step_end DONE
    run_step 3 "doosan-robot2 driver + DSR deps" bash "${RESOURCE_DIR}/app-install.sh" dsr
    run_step 4 "RealSense SDK"                   bash "${RESOURCE_DIR}/app-install.sh" realsense-sdk
    run_step 5 "RealSense ROS2 wrapper"          bash "${RESOURCE_DIR}/app-install.sh" realsense-ros
    # voice 는 colcon 앞에 둔다 — obtain_cobot2 뒤라 wakeword 모델이 이미 있어 import 검증이 돌고,
    # colcon 이 voice_processing 을 system python 으로 빌드할 때 그 shebang 이 여기서 깐 의존성을 본다.
    run_step 6 "host voice Python (direct)"      bash "${RESOURCE_DIR}/app-install.sh" voice
    run_step 7 "colcon build"                    bash "${RESOURCE_DIR}/app-install.sh" colcon
    # OPENAI_API_KEY 는 인스톨러가 다루지 않는다 — voice_processing 노드가 자기 패키지의
    # resource/.env 를 직접 읽으므로 사용자가 그 자리에 배치한다.
}

do_containers() {
    run_step $((8 + STEP_OFF)) "NVIDIA Container Toolkit" env ASSUME_YES=1 SKIP_IF_NO_GPU=1 bash "${RESOURCE_DIR}/app-install.sh" toolkit
    # 이미지는 yolo 하나뿐이다 — voice 는 컨테이너가 아니라 host 에서 직접 돈다.
    run_step $((9 + STEP_OFF)) "build container image (yolo dev-builder)" bash "${SCRIPT_DIR}/containers/build-all.sh"
}

echo "[setup-app] workspace=${DSR_WORKSPACE} | workspace:$([[ ${DO_WORKSPACE} -eq 1 ]] && echo on || echo off) containers:$([[ ${DO_CONTAINERS} -eq 1 ]] && echo on || echo off)$([[ ${RESET} -eq 1 ]] && echo ' | reset')"

[[ ${RESET} -eq 1 ]] && do_reset

# 아래 단계는 전부 sudo(apt / docker)를 쓴다. 비밀번호는 단계 배너와 heartbeat 가 시작되기 전에
# 한 번만 받는다 — 단계 도중에 물으면 그 프롬프트가 heartbeat 줄에 가려, 비밀번호를 다 치기도 전에
# 진행되는 것처럼 보인다. keepalive 가 colcon build 가 끝날 때까지 sudo 를 살려 둔다.
sudo_prime setup-app

[[ ${DO_WORKSPACE} -eq 1 ]] && do_workspace
[[ ${DO_CONTAINERS} -eq 1 ]] && do_containers

echo
echo "[setup-app] done."
[[ ${DO_WORKSPACE} -eq 1 ]] && echo "  workspace: source ${SCRIPT_DIR}/resources/activate.sh  (ROS + overlay)"
[[ ${DO_WORKSPACE} -eq 1 ]] && echo "  host voice: ros2 run voice_processing get_keyword  (mic = PipeWire default; override VOICE_MIC_DEVICE)"
[[ ${DO_CONTAINERS} -eq 1 ]] && echo "  containers: docker images | integrated run: bash containers/bringup.sh (yolo container + host voice)"
echo "  detailed log: ${LOG}"
