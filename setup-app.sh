#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# setup-app.sh — 앱 레이어(application layer) 셋업. 베이스 호스트 설치(install.sh)와 분리된 단계.
#
# install.sh = 베이스 호스트 환경만 담당(OS / NVIDIA / Docker / ROS2 + reboot + VS Code +
# DDS 튜닝 + 정적 IP + corecode). 이 스크립트 = 그 위에 cobot2 애플리케이션 올림:
#
#   workspace : doosan-robot2 드라이버 clone + DSR 의존성 + 에뮬레이터 → cobot2 소스 확인 → RealSense →
#               host voice Python(직접 설치) → colcon build.
#   containers: nvidia-container-toolkit → yolo 앱 컨테이너 이미지(:dev-builder — 소스 live-mount).
#
# cobot2 애플리케이션 소스 = 이 레포 미제공. 사용자가 ${DSR_WORKSPACE}/src/cobot2 에 직접 배치
# (아래 obtain_cobot2 참고 — 나중에 git clone / tarball 다운로드로 바꿀 수 있게 이 함수 하나로 격리). 소스 없으면
# workspace 단계 = 반쪽짜리 워크스페이스 만들어 런타임에서만 깨지는 대신, 곧바로 큰 소리로 실패.
#
# install.sh(그리고 그 reboot)가 끝난 뒤에 실행. 예전 reinstall-workspace.sh 를 대체.
#
# 콘솔 = [n/total] 단계 배너 + 살아있음 신호(heartbeat)만 표시. 각 단계의 상세 출력
# (apt / colcon / docker) = 레포 루트의 install_log 로. --verbose (또는 VERBOSE=1) = 그 출력을
# 콘솔에도 함께 흘려보냄. sudo 비밀번호 입력 = /dev/tty 사용 → 출력이 로그로 라우팅돼도 화면에 계속 표시.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="${SCRIPT_DIR}/resources"

# shellcheck source=resources/config.sh
source "${RESOURCE_DIR}/config.sh"
# shellcheck source=resources/lib.sh
source "${RESOURCE_DIR}/lib.sh"   # sudo_prime 제공
config_assert_set

# 단계별 상세 출력 = 여기로(install.sh 와 같은 install_log). --verbose 아니면 콘솔은 깔끔하게 유지.
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

# 실제 실행일 때 저작권 배너 출력(위의 --help 는 이미 종료됨).
print_copyright

# 진행률 분모 — [n/total] 표시에만 사용.
TOTAL=0
[[ ${DO_WORKSPACE} -eq 1 ]] && TOTAL=$(( TOTAL + 7 ))   # 7개: cobot2 확인 + m0609/onrobot + dsr + rs-sdk + rs-ros + voice-host + colcon
[[ ${DO_CONTAINERS} -eq 1 ]] && TOTAL=$(( TOTAL + 2 ))  # 2개: toolkit + yolo image
STEP_N=0
#######################################
# 단계 배너 출력 + 단계 카운터 1 증가.
# install.sh 와 같은 [n/total] 틀 포맷 사용.
# Globals:
#   STEP_N (1 증가), TOTAL (읽기)
# Arguments:
#   $* - 단계 이름(배너에 표시)
#######################################
step() {
    STEP_N=$(( STEP_N + 1 ))
    echo
    echo "============================================================"
    echo "[${STEP_N}/${TOTAL}] ${*}"
    echo "============================================================"
}

#######################################
# 라우팅된 단계가 도는 동안 "살아있음" 신호(heartbeat)를 화면에 표시.
# 콘솔이 조용해서 멈춘 것처럼 보이는 것 방지. 첫 출력은 2초 지연 —
# 단계 시작 때 뜨는 sudo 비밀번호 프롬프트(/dev/tty 사용) 덮어쓰기 방지.
# Arguments:
#   $1 - 단계 이름(경과 시간과 함께 표시)
# Outputs:
#   stderr 에 같은 줄을 갱신하며 진행 표시(캐리지 리턴 사용)
#######################################
_hb() {
    local name="$1" start="$SECONDS" e
    while :; do
        sleep 2
        e=$(( SECONDS - start ))
        printf '\r  ⋯ %s (%02d:%02d)\033[K' "$name" $(( e / 60 )) $(( e % 60 )) >&2
    done
}

#######################################
# 단계 배너 찍고 명령 실행. 상세 출력은 로그로,
# 콘솔에는 배너 + heartbeat 만 남김. VERBOSE=1 / --verbose 면
# 상세 출력을 콘솔에도 함께(tee) 표시.
# 실패하면 [FAIL] 한 줄 + 로그 경로 찍고 종료.
# (대화형·짧은 단계는 run 대신 step 을 직접 호출.)
# Globals:
#   VERBOSE, LOG (읽기)
# Arguments:
#   $1  - 단계 라벨
#   $2… - 실행할 명령과 인자
# Returns:
#   명령이 실패하면 그 종료코드로 스크립트를 종료
#######################################
run() {
    local label="$1"; shift
    step "${label}"
    { echo; echo "===== setup-app: ${label} — $(date '+%F %T') ====="; } >>"${LOG}"
    local rc=0 hb=""
    if [[ "${VERBOSE}" == 1 ]]; then
        set +e; "$@" 2>&1 | tee -a "${LOG}"; rc=${PIPESTATUS[0]}; set -e
    else
        if [[ -t 2 ]]; then _hb "${label}" & hb=$!; fi
        "$@" >>"${LOG}" 2>&1 || rc=$?
        if [[ -n "${hb}" ]]; then
            kill "${hb}" 2>/dev/null || true
            wait "${hb}" 2>/dev/null || true
            printf '\r\033[K' >&2
        fi
    fi
    if [[ ${rc} -ne 0 ]]; then
        echo "[setup-app] FAILED: ${label} (rc=${rc}) — see ${LOG}" >&2
        exit "${rc}"
    fi
}

#######################################
# cobot2 애플리케이션 소스를 ${DSR_WORKSPACE}/src/cobot2 로 가져옴.
# 현재 정책: 사용자가 직접 배치 — 존재만 확인, 없으면 큰 소리로 실패.
# 소스 취득 방식 바꿀 때(git clone / tarball 다운로드) 이 함수 본문만
# 고치면 되도록 격리한 지점(예: `git clone <url> "${cobot2}"`).
# Globals:
#   DSR_WORKSPACE (읽기)
# Returns:
#   소스가 있으면 0, 없으면 안내 메시지 출력 후 종료(exit 1)
#######################################
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

#######################################
# 통합 bringup(m0609_rg2_bringup)과 그 외부 의존(onrobot-ros2)을 워크스페이스에 준비.
#
# M0609 레포는 공개 저장소라 없으면 clone 하고, 이미 있으면 손대지 않는다(개발 중인 작업본 보호).
# 워크스페이스에는 레포 전체가 아니라 bringup 패키지 하나만 심볼릭 링크한다 — 같은 레포의
# m0609_rg2_moveit 은 moveit 스택 전체를 rosdep 으로 끌어오는데 이 설치엔 쓰이지 않는다.
# (colcon 은 심볼릭 링크된 패키지 디렉토리를 그대로 인식한다 — 실측 확인.)
# onrobot-ros2 는 M0609 레포가 추적하지 않는 외부 패키지 → 커밋 SHA 로 핀 고정해 별도 clone.
#
# 멱등: clone 은 .git 존재 시 skip, 링크는 ln -sfn 으로 매번 같은 결과.
# Globals:
#   DSR_WORKSPACE, M0609_REPO_URL, M0609_REF, M0609_REPO_DIR,
#   ONROBOT_REPO_URL, ONROBOT_COMMIT (읽기)
# Returns:
#   준비되면 0, 링크 자리에 실제 디렉토리가 있으면 안내 후 종료(exit 1)
#######################################
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

#######################################
# doosan-robot2 clone + build/install/log 지우고 처음부터 다시 만들 준비.
# cobot2(사용자가 직접 둔 소스)는 보존. --yes 없으면 먼저 확인 요청,
# TTY 없어 물어볼 수 없으면 종료.
# Globals:
#   ASSUME_YES, DSR_WORKSPACE (읽기)
#######################################
do_reset() {
    # 지워도 되는 것만 지움 — 다시 clone·빌드하면 복구됨. cobot2(사용자 배치본)는 그대로 유지.
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
    step "cobot2 source (verify)"; obtain_cobot2   # 빠른 확인 — 콘솔에 그대로 표시(로그로 안 보냄)
    step "m0609 bringup + onrobot-ros2"; obtain_m0609
    run "doosan-robot2 driver + DSR deps" bash "${RESOURCE_DIR}/app-install.sh" dsr
    run "RealSense SDK"                   bash "${RESOURCE_DIR}/app-install.sh" realsense-sdk
    run "RealSense ROS2 wrapper"          bash "${RESOURCE_DIR}/app-install.sh" realsense-ros
    # voice-host: colcon 앞에 둠 — obtain_cobot2 뒤라 wakeword 모델이 있어 import 게이트가 돌고,
    # colcon 이 voice_processing 을 system python 으로 빌드하면 그 shebang 이 여기서 깐 deps 를 본다.
    run "host voice Python (direct)"      bash "${RESOURCE_DIR}/app-install.sh" voice
    run "colcon build"                    bash "${RESOURCE_DIR}/app-install.sh" colcon
    # OPENAI_API_KEY 는 인스톨러가 다루지 않음 — voice_processing 노드가 자기 패키지 resource/.env
    # (colcon 빌드 내장)를 직접 읽는다. 사용자가 별도 안내에 따라 그 위치에 직접 배치.
}

do_containers() {
    run "NVIDIA Container Toolkit" env ASSUME_YES=1 SKIP_IF_NO_GPU=1 bash "${RESOURCE_DIR}/app-install.sh" toolkit
    # yolo 이미지만 빌드(voice 는 host 실행 — do_workspace 참조). ROS_DOMAIN_ID 은 묻지도 주입하지도
    # 않음 — 학생이 자기 ~/.bashrc 에 `export ROS_DOMAIN_ID=<n>`(학습 과제). 안 하면 기본 0 이라 host↔컨테이너 일치.
    run "build container image (yolo dev-builder)" bash "${SCRIPT_DIR}/containers/build-all.sh"
}

echo "[setup-app] workspace=${DSR_WORKSPACE} | workspace:$([[ ${DO_WORKSPACE} -eq 1 ]] && echo on || echo off) containers:$([[ ${DO_CONTAINERS} -eq 1 ]] && echo on || echo off)$([[ ${RESET} -eq 1 ]] && echo ' | reset')"

[[ ${RESET} -eq 1 ]] && do_reset

# 아래 모든 단계가 sudo(apt / docker) 사용. 비밀번호를 여기서 딱 한 번 미리 받음 — 단계 배너와
# heartbeat 가 시작되기 전에. 안 그러면 첫 라우팅 단계의 sudo 프롬프트가 heartbeat 뒤에 가려져,
# 비밀번호를 다 치기도 전에 진행되는 것처럼 보임. keepalive 가 colcon build 끝날 때까지 sudo 살려둠.
sudo_prime setup-app

[[ ${DO_WORKSPACE} -eq 1 ]] && do_workspace
[[ ${DO_CONTAINERS} -eq 1 ]] && do_containers

echo
echo "[setup-app] done."
[[ ${DO_WORKSPACE} -eq 1 ]] && echo "  workspace: source ${SCRIPT_DIR}/resources/activate.sh  (ROS + overlay)"
[[ ${DO_WORKSPACE} -eq 1 ]] && echo "  host voice: ros2 run voice_processing get_keyword  (mic = PipeWire default; override VOICE_MIC_DEVICE)"
[[ ${DO_CONTAINERS} -eq 1 ]] && echo "  containers: docker images | integrated run: bash containers/bringup.sh (yolo container + host voice)"
echo "  detailed log: ${LOG}"
