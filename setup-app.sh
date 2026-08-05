#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# setup-app.sh · base 호스트 설치(install.sh) 위에 cobot2 애플리케이션 계층 적재
#
#   workspace : cobot2 소스 확인 → m0609 bringup + onrobot → doosan-robot2 드라이버 + DSR 의존성 →
#               RealSense SDK / ROS2 wrapper → host voice Python → colcon build
#   containers: nvidia-container-toolkit → yolo 이미지(:dev-builder = 소스 live-mount 개발용)
#
# 실행 시점 = install.sh + 그 재부팅 완료 후
# 출력 라우팅
#   콘솔 = [n/total] 배너 + heartbeat 만
#   apt / colcon / docker 상세 = install_log 행(--verbose 면 콘솔에도 동시)
#   sudo 프롬프트 = /dev/tty 행 → 로그 라우팅에 삼켜지지 않음
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

# 배너 출력 조건 = 실제 실행일 때만(--help = 이미 exit)
print_copyright

# 진행률 분모 = [n/total] 표시 전용
TOTAL=0
[[ ${DO_WORKSPACE} -eq 1 ]] && TOTAL=$(( TOTAL + 7 ))   # 7개: cobot2 확인 + m0609/onrobot + dsr + rs-sdk + rs-ros + voice-host + colcon
[[ ${DO_CONTAINERS} -eq 1 ]] && TOTAL=$(( TOTAL + 2 ))  # 2개: toolkit + yolo image

# 컨테이너 단독 실행 = 워크스페이스 7단계 제외 → 번호 앞당김
STEP_OFF=0
[[ ${DO_WORKSPACE} -eq 1 ]] || STEP_OFF=-7

# setup-app = 재개 개념 없음 → state 미기록, 배너와 로그만 사용
# 아래 run_step/step_begin 의 단계 이름 = "cobot2 source (verify)" 같은 사람이 읽는 문구
#   install.sh 의 state 키(a01_docker 류 식별자)와 달리 공백·괄호 포함
#   이 값의 state 파일 기록/조회 사용 조건 = STEP_STATE=1(_state_set 의 grep -qE / sed -i)
#   그 경로에서 괄호 = 정규식 그룹으로 해석 → 파손
#   → 1 로 전환하려면 라벨을 전부 state-safe 키로 먼저 변경
STEP_STATE=0
STEPS_TOTAL="${TOTAL}"
LOG_FILE="${LOG}"

# cobot2 소스의 ${DSR_WORKSPACE}/src/cobot2 존재 여부 확인
#   현 정책 = 사용자 직접 배치 → 존재 확인만 수행
#   부재 시 = 반쪽 워크스페이스 생성 후 런타임 파손 대신 이 지점에서 정지
# 취득 방식을 git clone 등으로 변경할 때의 수정 지점 = 이 함수 하나(격리 목적)
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

# 통합 bringup(m0609_rg2_bringup) + 그 외부 의존(onrobot-ros2) 워크스페이스 준비
#
# M0609 레포 clone 조건 = 부재 시에만
#   기존 존재 = 개발 중 작업본 가능성 → 불건드림
# 워크스페이스 링크 대상 = 레포 전체 아님, bringup 패키지 하나만 심볼릭 링크
#   같은 레포의 m0609_rg2_moveit = rosdep 으로 moveit 스택 전체 유입 + 이 설치에서 미사용
#   colcon 의 심볼릭 링크 패키지 디렉토리 인식 = 실측 확인
# onrobot-ros2 = M0609 레포가 추적하지 않는 외부 패키지
#   → 커밋 SHA 핀 고정 + 별도 clone
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

    # 링크 자리에 실제 디렉토리 존재 → ln -sfn 이 그 안쪽에 링크 생성 → 조용한 불일치
    # 사용자가 손으로 복사해 둔 경우 가능 → 삭제 금지, 정지 처리
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
    # clone skip 경로에서도 핀 재적용
    #   → 브랜치가 옮겨져 있어도 같은 커밋으로 수렴
    git -C "${onrobot}" checkout --quiet "${ONROBOT_COMMIT}"
    echo "setup-app: onrobot-ros2 pinned at ${ONROBOT_COMMIT}"
}

# doosan-robot2 clone + build/install/log 삭제 → 처음부터 재생성 준비
#   삭제 범위 = 재취득·재빌드로 복구되는 것만
#   사용자가 직접 배치한 cobot2 소스 = 불건드림
# --yes 부재 → 사전 확인 수령
# 질문할 TTY 부재 → 종료
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
    # m0609_rg2_bringup = 심볼릭 링크 → 삭제해도 원본(${M0609_REPO_DIR}) 보존
    # onrobot-ros2 = 핀 고정 clone → 재취득 시 같은 커밋으로 복구
    echo "[setup-app] reset: wiping doosan-robot2 / onrobot-ros2 / m0609 link + build/install/log (cobot2 and ${M0609_REPO_DIR} kept)"
    rm -rf "${DSR_WORKSPACE}/src/doosan-robot2" \
           "${DSR_WORKSPACE}/src/onrobot-ros2" \
           "${DSR_WORKSPACE}/build" "${DSR_WORKSPACE}/install" "${DSR_WORKSPACE}/log"
    rm -f  "${DSR_WORKSPACE}/src/m0609_rg2_bringup"
}

do_workspace() {
    # 앞의 두 단계 = 즉시 끝나는 확인 → run_step 아님, step_begin/step_end 사용
    #   출력 = 로그 우회 없이 콘솔에 그대로 노출
    step_begin 1 "${TOTAL}" "cobot2 source (verify)"; obtain_cobot2; step_end DONE
    step_begin 2 "${TOTAL}" "m0609 bringup + onrobot-ros2"; obtain_m0609; step_end DONE
    run_step 3 "doosan-robot2 driver + DSR deps" bash "${RESOURCE_DIR}/app-install.sh" dsr
    run_step 4 "RealSense SDK"                   bash "${RESOURCE_DIR}/app-install.sh" realsense-sdk
    run_step 5 "RealSense ROS2 wrapper"          bash "${RESOURCE_DIR}/app-install.sh" realsense-ros
    # voice 배치 = colcon 앞
    #   obtain_cobot2 뒤 → wakeword 모델 이미 존재 → import 검증 수행 가능
    #   colcon 이 voice_processing 을 system python 으로 빌드 → 그 shebang 이 여기서 깐 의존성 참조
    run_step 6 "host voice Python (direct)"      bash "${RESOURCE_DIR}/app-install.sh" voice
    run_step 7 "colcon build"                    bash "${RESOURCE_DIR}/app-install.sh" colcon
    # OPENAI_API_KEY = 인스톨러 미취급
    #   voice_processing 노드 = 자기 패키지의 resource/.env 직접 독해
    #   → 사용자가 그 자리에 배치
}

do_containers() {
    run_step $((8 + STEP_OFF)) "NVIDIA Container Toolkit" env ASSUME_YES=1 SKIP_IF_NO_GPU=1 bash "${RESOURCE_DIR}/app-install.sh" toolkit
    # 이미지 = yolo 하나뿐
    #   voice = 컨테이너 아님, host 직접 실행
    run_step $((9 + STEP_OFF)) "build container image (yolo dev-builder)" bash "${SCRIPT_DIR}/containers/build-all.sh"
}

echo "[setup-app] workspace=${DSR_WORKSPACE} | workspace:$([[ ${DO_WORKSPACE} -eq 1 ]] && echo on || echo off) containers:$([[ ${DO_CONTAINERS} -eq 1 ]] && echo on || echo off)$([[ ${RESET} -eq 1 ]] && echo ' | reset')"

[[ ${RESET} -eq 1 ]] && do_reset

# 아래 단계 전부 = sudo(apt / docker) 사용
# 비밀번호 = 단계 배너·heartbeat 시작 전 1회 수령
#   단계 도중 질문 → 프롬프트가 heartbeat 줄에 가림
#   → 비밀번호 입력 완료 전에 진행되는 것처럼 보임
# keepalive = colcon build 종료까지 sudo 유지
sudo_prime setup-app

[[ ${DO_WORKSPACE} -eq 1 ]] && do_workspace
[[ ${DO_CONTAINERS} -eq 1 ]] && do_containers

echo
echo "[setup-app] done."
[[ ${DO_WORKSPACE} -eq 1 ]] && echo "  workspace: source ${SCRIPT_DIR}/resources/activate.sh  (ROS + overlay)"
[[ ${DO_WORKSPACE} -eq 1 ]] && echo "  host voice: ros2 run voice_processing get_keyword  (mic = PipeWire default; override VOICE_MIC_DEVICE)"
[[ ${DO_CONTAINERS} -eq 1 ]] && echo "  containers: docker images | integrated run: bash containers/bringup.sh (yolo container + host voice)"
echo "  detailed log: ${LOG}"
