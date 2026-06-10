#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# install.sh — host 워크스테이션 셋업 단일 진입점 (a01~a04 전체 시퀀스).
#
# a01~a04 오케스트레이터의 모든 step + DDS 튜닝 + NVIDIA Container Toolkit + 컨테이너 이미지 확보를 하나의
# 연속 시퀀스([n/16])로 실행한다.
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
# (--unattended 면 reboot·재개가 자동이라 수동 재실행 불필요 — GUI 세션 전제.)
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
# shellcheck source=resources/env-load.sh
source "${RESOURCE_DIR}/env-load.sh"
# shellcheck source=resources/unattended.sh
source "${RESOURCE_DIR}/unattended.sh"
config_assert_set

STEPS_TOTAL=16
# shellcheck source=resources/run-step.sh
source "${RESOURCE_DIR}/run-step.sh"

usage() {
    cat <<'EOF'
install.sh — host 셋업 단일 진입점 (a01~a04 + DDS 튜닝 + NVIDIA Container Toolkit + 컨테이너 이미지 + 네트워크 고정 IP, 전체 16 step)

  bash install.sh             전체 시퀀스 실행 (이미 완료된 step 은 skip)
  bash install.sh --unattended  무인 설치 — 시작 시 OPENAI_API_KEY + confirm 1회 후 reboot 까지
                                자동 진행, 복귀 시 자동 재개(GUI 세션 필요, 복귀 후 sudo 비번 1회)
  bash install.sh --verbose   각 step 의 상세 출력(colcon n/total, apt %)을 콘솔에도 표시
  bash install.sh --status    현재 진행 상태(state) 출력
  bash install.sh --reset     state 초기화 (confirm 후 — 모든 step 재실행)
  bash install.sh --help      이 도움말

기본은 콘솔에 [n/total] 진행률 + step 경과시간만 표시하고 상세 출력은
~/.ros2_jazzy_test/install.log 로 빠집니다. --verbose 또는 VERBOSE=1 환경변수로
상세 출력을 콘솔에도 표시할 수 있습니다(개별 a0N 스크립트는 VERBOSE=1 bash a0N-...sh).

reboot(step 6) 후에는 다시 'bash install.sh' 를 실행하면 step 7 부터 이어집니다.
개별 스테이지만 재실행하려면 a01-prerequirements.sh / a02-robot-camera.sh /
a03-vs-code-install.sh / a04-voice-precheck.sh 를 직접 실행하세요.
EOF
}

# --verbose/-v 는 서브커맨드와 직교하므로 먼저 분리해 VERBOSE 로 흡수하고 나머지만 남긴다.
# run-step.sh 가 같은 셸에서 VERBOSE 를 읽는다(export 는 자식 resource 스크립트 대비).
VERBOSE="${VERBOSE:-0}"
UNATTENDED="${UNATTENDED:-0}"
__args=()
for __a in "$@"; do
    case "$__a" in
        -v|--verbose) VERBOSE=1 ;;
        --unattended) UNATTENDED=1 ;;
        *) __args+=("$__a") ;;
    esac
done
export VERBOSE UNATTENDED
# 빈 배열 + set -u → unbound var 오류(bash<4.4) 방지용 확장 guard. "${__args[@]}" 로 단순화 금지.
set -- "${__args[@]+"${__args[@]}"}"

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

# sudo keepalive — 긴 step(드라이버/colcon) 중 sudo 캐시를 60s 마다 갱신해 재입력을 막는다.
# 무인 재개(복귀 후 sudo 비번 1회) 흐름에서도 끝까지 비번 재입력이 없게 한다. 종료 시 정리.
# subshell 안에서 set +e — sudo -n 일시 실패나 sleep 인터럽트로 keepalive 가 조용히 죽지
# 않게 한다. 부모가 살아있는 동안만 돌고, 부모 종료 시 아래 EXIT trap 으로 정리.
( set +e; while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 60; done ) &
_SUDO_KA_PID=$!
trap 'kill "${_SUDO_KA_PID}" 2>/dev/null || true' EXIT

# 자식 본문 내부의 예기치 못한 실패 위치를 보강 (run_step 의 step_end_fail 과 직교).
trap 'echo "[install] 실패: line $LINENO" >&2' ERR

# --- 무인 설치(--unattended) 사전/재개 처리 ----------------------------
# 첫 실행(reboot 전): OPENAI_API_KEY 선수집 + 진행 confirm 1회 + 복귀 자동재개 등록.
#   → step 6 reboot 후 step12(voice)는 키가 이미 있어 비대화 통과, reboot 도 재confirm 없음.
# 재개(reboot 후): autostart 항목을 즉시 제거(1회용 — 로그인마다 재발화 방지). sudo 는 이 터미널
#   에서 위 sudo -v 로 1회 입력됨.
if [[ "${UNATTENDED}" == "1" ]]; then
    if step_should_skip a01_reboot; then
        unattended_remove_resume
    elif [[ -t 0 ]]; then
        unattended_collect_secrets "${SCRIPT_DIR}" || true
        confirm_or_abort "무인 설치를 진행합니다 — 중간에 1회 자동 재부팅하고, 복귀(로그인) 시 자동으로 이어집니다(터미널 자동 오픈, sudo 비번 1회). 계속할까요?"
        unattended_register_resume "${SCRIPT_DIR}"
    else
        echo "[install] 경고: --unattended 인데 비대화형 셸 — 자동 재개를 등록할 수 없습니다." >&2
        echo "          GUI 세션에서 실행하거나 reboot 후 수동 재실행하세요." >&2
    fi
fi

# --- step 1~5: 사전준비 (a01: 커널 베이스라인 / NVIDIA / Docker / ROS2 jazzy / extras) ---
# kernel-baseline 을 nvidia 보다 먼저: HWE 커널 메타 + 헤더 + modules-extra 를 보장해야
# nvidia 모듈이 반쪽 커널을 끌어오는 brick 과 DKMS 헤더 누락을 둘 다 차단한다.
run_step 1 a01_kernel_baseline bash "${RESOURCE_DIR}/kernel-baseline.sh"
run_step 2 a01_nvidia_driver   bash "${RESOURCE_DIR}/nvidia-driver-install.sh"
run_step 3 a01_docker          bash "${RESOURCE_DIR}/docker-install.sh"
run_step 4 a01_ros2_desktop    bash "${RESOURCE_DIR}/ros2-desktop-main.sh"
run_step 5 a01_ros2_extras     bash "${RESOURCE_DIR}/ros2-install.sh"

# --- step 6: reboot 경계 (a01) ---
# run_step 으로 감싸지 못한다: reboot 은 프로세스를 종료하고, 이후의 모든 후속 step(7 이후)은
# 재부팅 후 실행되어야 한다. reboot 전에 DONE 을 디스크에 기록해 재부팅 후 재실행이 이 단계를
# 건너뛰도록 한다 (무한 reboot 루프 방지).
# confirm 거부/비대화형 abort 시엔 DONE 이 기록되지 않아 a01_reboot 이 RUNNING 으로 남는다.
# skip 판정은 DONE 만 보므로 다음 실행에서 reboot 를 다시 묻는다 — reboot 동의 전이므로 의도된 동작.
if ! step_should_skip a01_reboot; then
    step_begin 6 "${STEPS_TOTAL}" a01_reboot
    if [[ "${UNATTENDED}" == "1" ]]; then
        echo "[install] 무인 모드: 자동 재부팅합니다(시작 시 동의 적용)."
    else
        confirm_or_abort "사전준비(커널/드라이버/Docker/ROS2) 완료. 드라이버·docker 그룹 적용을 위해 지금 재부팅할까요?"
    fi
    step_end_ok
    echo
    if [[ "${UNATTENDED}" == "1" ]]; then
        echo ">>> 재부팅합니다. 복귀(로그인) 시 자동 재개됩니다 — 수동 실행 불필요."
    else
        echo ">>> 재부팅합니다. 복귀 후 'bash install.sh' 를 다시 실행하면 step 7 부터 이어집니다."
    fi
    sudo reboot
fi

# reboot 복귀 후 조기 점검: 부팅된 커널에 wifi/USB 드라이버(modules-extra)가 있는지 확인.
# 엉뚱한(반쪽) 커널로 부팅됐다면 뒤 단계(RealSense DKMS 등) 진행 전에 알려준다.
__running="$(uname -r)"
if [[ ! -d "/lib/modules/${__running}/kernel/drivers/net/wireless" ]]; then
    echo "[install] 경고: 현재 커널(${__running})에 modules-extra 가 없어 보입니다 — wifi/USB 입력 누락 가능." >&2
    echo "          GRUB 에서 modules-extra 가 있는 커널로 부팅하거나 docs/TROUBLESHOOTING.md 의 커널 모듈 항목 참조." >&2
fi

# --- step 7~10: 로봇/카메라 (a02: DSR + RealSense + colcon 빌드) ---
run_step 7  a02_dsr_project   bash "${RESOURCE_DIR}/dsr-project-install.sh"
run_step 8  a02_realsense_sdk bash "${RESOURCE_DIR}/realsense-sdk-install.sh"
run_step 9  a02_realsense_ros bash "${RESOURCE_DIR}/realsense-ros-install.sh"
run_step 10 a02_colcon_build  bash "${RESOURCE_DIR}/colcon-build.sh"

# --- step 11: 개발 도구 (a03: VS Code) ---
run_step 11 a03_vscode bash "${RESOURCE_DIR}/vscode-install.sh"

# --- step 12: 음성 사전 점검 (a04: .env 자격증명 + Docker Hub 로그인 안내) ---
run_step --interactive 12 a04_voice_env bash "${RESOURCE_DIR}/voice-env-check.sh"

# --- step 13: DDS 튜닝 (CycloneDDS 버퍼 + 유선 NIC whitelist 자동 설정) ---
# host 노드·컨테이너 공통 cyclonedds 환경을 결정적으로 구성. a0N 스테이지 스크립트엔
# 없고 install.sh 또는 단독(bash resources/dds-tuning.sh) 으로만 실행한다.
run_step 13 dds_tuning bash "${RESOURCE_DIR}/dds-tuning.sh"

# --- step 14: NVIDIA Container Toolkit (reboot 이후 — GPU 드라이버 모듈 로드 완료 상태) ---
# reboot 전(a01/docker-install)에 설치하면 드라이버 커널 모듈이 미로드라 toolkit 작업이
# 실패한다. 그래서 step6 reboot 뒤로 분리해 GPU 동작이 보장된 상태에서 설치한다.
# 컨테이너(yolo)가 host GPU 를 쓰려면 필요(compose nvidia device reservation / `--gpus`).
# SKIP_IF_NO_GPU=1: GPU 없는 host 전용 머신은 정상 skip(드라이버 부재를 에러로 안 봄).
# ASSUME_YES=1: docker 재시작 동의 자동(비대화 흐름).
run_step 14 nvidia_container_toolkit \
    env ASSUME_YES=1 SKIP_IF_NO_GPU=1 bash "${SCRIPT_DIR}/resources/nvidia-container-toolkit-install.sh"

# --- step 15: 애플리케이션 컨테이너 이미지 확보 (yolo / voice) ---
# fetch-images.sh 가 공개 구글 드라이브에서 빌드 산출물(docker save tar)을 받아 SHA256 검증 후
# docker load 한다(빌드 없이 빠른 재현). 이미지가 이미 로컬에 있으면 skip(멱등). 실패 시 state
# 미DONE 으로 남아 재실행 시 이 step 만 재시도한다.
# 이미지를 직접 빌드/검증하는 제작 머신은 별도로 `bash containers/build-all.sh` 를 쓴다
# (두 이미지 빌드 + secret 위생 스캔 + import/모델로드 smoke). 그 산출물을 드라이브에 올리면
# 다른 머신은 본 step 으로 받아 재현한다. file ID/SHA256 은 resources/config.sh 에 핀.
run_step 15 container_fetch bash "${SCRIPT_DIR}/containers/fetch-images.sh"

# --- step 16: ethernet 고정 IP (로봇 LAN: .1 그리퍼 / .100 로봇 / .30 host) ---
# 모든 설치 후 유선 NIC 를 로봇 LAN 고정 IP 로 설정(nmcli). 게이트웨이/DNS 없음 → wifi
# 인터넷 유지. 멱등. confirm 없음(reversible; 무인 모드는 시작 시 1회 동의로 포괄).
run_step 16 network_static_ip bash "${RESOURCE_DIR}/network-static-ip.sh"

# 무인 재개 autostart 정리(재개 진입 시 이미 제거됐으면 no-op — 멱등).
unattended_remove_resume 2>/dev/null || true

state_dump
echo "install: 전체 16 step 완료 — host 셋업 + 컨테이너 이미지 + 네트워크 고정 IP 종료."
