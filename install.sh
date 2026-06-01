#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# install.sh — host 워크스테이션 셋업 단일 진입점 (a01~a04 전체 시퀀스).
#
# a01~a04 오케스트레이터의 모든 step 을 하나의 연속 시퀀스([n/13])로 실행한다.
# 같은 state 파일을 공유하므로 개별 오케스트레이터(bash a0N-...sh)로 이미 완료한 step 은
# 자동 skip 된다. 특정 스테이지만 다시 돌리려면 해당 a0N 스크립트를 직접 실행하면 된다.
#
# 사용법:
#   bash install.sh            전체 시퀀스 실행 (완료 step skip)
#   bash install.sh --status   현재 진행 상태(state) 출력
#   bash install.sh --reset    state 초기화 (confirm 후 — 모든 step 재실행)
#   bash install.sh --help
#
# reboot(step 6) 후에는 다시 'bash install.sh' 를 실행하면 step 7 부터 이어진다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="${SCRIPT_DIR}/resources"

# root 직접 실행 금지 — HOME=/root 가 되어 state / docker 그룹 / 워크스페이스가 /root 로
# 잘못 들어가 일반 사용자 환경에 반영되지 않는다. 필요한 명령은 자식이 sudo 로 호출한다.
if [[ "$(id -u)" -eq 0 ]]; then
    echo "install: sudo 로 실행하지 마세요. 일반 사용자로 'bash install.sh' 실행." >&2
    echo "         (필요한 명령은 스크립트가 알아서 sudo 로 호출합니다.)" >&2
    exit 1
fi

# shellcheck source=resources/config.sh
source "${RESOURCE_DIR}/config.sh"
# shellcheck source=resources/state.sh
source "${RESOURCE_DIR}/state.sh"
# shellcheck source=resources/confirm.sh
source "${RESOURCE_DIR}/confirm.sh"
config_assert_set

STEPS_TOTAL=13
# shellcheck source=resources/run-step.sh
source "${RESOURCE_DIR}/run-step.sh"

usage() {
    cat <<'EOF'
install.sh — host 셋업 단일 진입점 (a01~a04 통합, 전체 13 step)

  bash install.sh            전체 시퀀스 실행 (이미 완료된 step 은 skip)
  bash install.sh --status   현재 진행 상태(state) 출력
  bash install.sh --reset    state 초기화 (confirm 후 — 모든 step 재실행)
  bash install.sh --help     이 도움말

reboot(step 6) 후에는 다시 'bash install.sh' 를 실행하면 step 7 부터 이어집니다.
개별 스테이지만 재실행하려면 a01-prerequirements.sh / a02-robot-camera.sh /
a03-vs-code-install.sh / a04-voice-precheck.sh 를 직접 실행하세요.
EOF
}

# --- 인자 디스패치 (set -u 하 ${1:-} 필수) ---
case "${1:-}" in
    --status) state_dump; exit 0 ;;
    --reset)
        confirm_or_abort "state 파일을 초기화할까요? (재설치 시 모든 step 재실행)"
        rm -f "$STATE_FILE"
        echo "install: state 초기화 완료 ($STATE_FILE 삭제)."
        exit 0
        ;;
    --help|-h) usage; exit 0 ;;
    "") : ;;
    *) echo "install: 알 수 없는 옵션 '$1'" >&2; usage; exit 2 ;;
esac

# --- preflight: 잘못된 환경에서 절반 진행 후 실패하는 사고를 사전 차단 ---
if [[ ! -f /etc/os-release ]]; then
    echo "install: /etc/os-release 를 읽을 수 없습니다 — Ubuntu 환경인지 확인하세요." >&2
    exit 1
fi
# shellcheck source=/dev/null
host_codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
if [[ "$host_codename" != "$UBUNTU_CODENAME" ]]; then
    echo "install: 이 installer 는 Ubuntu '$UBUNTU_CODENAME' 대상입니다 (현재: '${host_codename:-unknown}')." >&2
    exit 1
fi
if ! sudo -v; then
    echo "install: sudo 권한을 확인할 수 없습니다. sudo 가능한 일반 사용자로 실행하세요." >&2
    exit 1
fi

# 자식 본문 내부의 예기치 못한 실패 위치를 보강 (run_step 의 step_end_fail 과 직교).
trap 'echo "[install] 실패: line $LINENO" >&2' ERR

# --- step 1~5: 사전준비 (a01: 커널 베이스라인 / NVIDIA / Docker / ROS2 jazzy / extras) ---
# kernel-baseline 을 nvidia 보다 먼저: HWE 커널 메타 + 헤더 + modules-extra 를 보장해야
# nvidia 모듈이 반쪽 커널을 끌어오는 brick 과 DKMS 헤더 누락을 둘 다 차단한다.
run_step 1 a01_kernel_baseline bash "${RESOURCE_DIR}/kernel-baseline.sh"
run_step 2 a01_nvidia_driver   bash "${RESOURCE_DIR}/nvidia-driver-install.sh"
run_step 3 a01_docker          bash "${RESOURCE_DIR}/docker-install.sh"
run_step 4 a01_ros2_desktop    bash "${RESOURCE_DIR}/ros2-desktop-main.sh"
run_step 5 a01_ros2_extras     bash "${RESOURCE_DIR}/ros2-install.sh"

# --- step 6: reboot 경계 (a01) ---
# run_step 으로 감싸지 못한다: reboot 은 프로세스를 종료하고, 이후 step 7~12 는 재부팅 후
# 실행되어야 한다. reboot 전에 DONE 을 디스크에 기록해 재부팅 후 재실행이 이 단계를
# 건너뛰도록 한다 (무한 reboot 루프 방지).
# confirm 거부/비대화형 abort 시엔 DONE 이 기록되지 않아 a01_reboot 이 RUNNING 으로 남는다.
# skip 판정은 DONE 만 보므로 다음 실행에서 reboot 를 다시 묻는다 — reboot 동의 전이므로 의도된 동작.
if ! step_should_skip a01_reboot; then
    step_begin 6 "${STEPS_TOTAL}" a01_reboot
    confirm_or_abort "사전준비(커널/드라이버/Docker/ROS2) 완료. 드라이버·docker 그룹 적용을 위해 지금 재부팅할까요?"
    step_end_ok
    echo
    echo ">>> 재부팅합니다. 복귀 후 'bash install.sh' 를 다시 실행하면 step 7 부터 이어집니다."
    sudo reboot
fi

# reboot 복귀 후 조기 점검: 부팅된 커널에 wifi/USB 드라이버(modules-extra)가 있는지 확인.
# 엉뚱한(반쪽) 커널로 부팅됐다면 뒤 단계(RealSense DKMS 등) 진행 전에 알려준다.
__running="$(uname -r)"
if [[ ! -d "/lib/modules/${__running}/kernel/drivers/net/wireless" ]]; then
    echo "[install] 경고: 현재 커널(${__running})에 modules-extra 가 없어 보입니다 — wifi/USB 입력 누락 가능." >&2
    echo "          GRUB 에서 modules-extra 가 있는 커널로 부팅하거나 docs/TROUBLESHOOTING.md 의 커널 모듈 항목 참조." >&2
fi

# --- step 7~11: 로봇/카메라 (a02: DSR + RealSense + host Python + colcon 빌드) ---
run_step 7  a02_dsr_project      bash "${RESOURCE_DIR}/dsr-project-install.sh"
run_step 8  a02_realsense_sdk    bash "${RESOURCE_DIR}/realsense-sdk-install.sh"
run_step 9  a02_realsense_ros    bash "${RESOURCE_DIR}/realsense-ros-install.sh"
# host application Python(venv) 은 colcon 빌드 전에: 빌드를 venv 하에서 돌려야 ament_python
# entry_point shebang 이 venv python 을 가리켜 `ros2 run` 이 app Python 을 본다(colcon-build.sh).
run_step 10 a02_host_python_deps bash "${RESOURCE_DIR}/host-python-deps.sh"
run_step 11 a02_colcon_build     bash "${RESOURCE_DIR}/colcon-build.sh"

# --- step 12: 개발 도구 (a03: VS Code) ---
run_step 12 a03_vscode bash "${RESOURCE_DIR}/vscode-install.sh"

# --- step 13: 음성 점검 (a04: .env 자격증명 + wakeword 모델 로드 smoke) ---
run_step 13 a04_voice_env bash "${RESOURCE_DIR}/voice-env-check.sh"

state_dump
echo "install: 전체 13 step 완료 — host 셋업 종료."
