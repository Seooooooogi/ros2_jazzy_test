#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# install.sh · host 워크스테이션 base 환경 설치의 단일 진입점
#   9 단계 = 커널 / NVIDIA / Docker / ROS2 → reboot → VS Code → DDS 튜닝 → 정적 IP
#   앱 계층(DSR / RealSense / colcon / host voice / 컨테이너) = setup-app.sh 담당
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="${SCRIPT_DIR}/resources"

# root 실행 금지 = state · docker 그룹 · 워크스페이스가 전부 /root 아래로 생성됨
if [[ "$(id -u)" -eq 0 ]]; then
    echo "install: do not run with sudo. Run 'bash install.sh' as a regular user." >&2
    echo "         (the script calls the necessary commands via sudo on its own.)" >&2
    exit 1
fi

# shellcheck source=resources/config.sh
source "${RESOURCE_DIR}/config.sh"
# shellcheck source=resources/lib.sh
source "${RESOURCE_DIR}/lib.sh"
config_assert_set
STEPS_TOTAL="$(install_steps_total)"

usage() {
    cat <<'EOF'
install.sh — single entry point for the BASE host environment (kernel/NVIDIA/Docker/ROS2 + reboot + VS Code + DDS tuning + static network IP, 9 steps total)

  bash install.sh             run the full sequence (skip already-completed steps)
  bash install.sh --verbose   also show each step's detailed output + warnings/errors on the console
  bash install.sh --no-nvidia-driver
                              skip the NVIDIA driver step (assumes the driver is already installed by
                              other means — for non-target machines). Recorded as SKIPPED in the state,
                              so it stays skipped across the mid-install reboot. Combine with any subcommand.
  bash install.sh --status    print the current progress (state)
  bash install.sh --reset     reset the state (after confirm — re-run all steps)
  bash install.sh --help      this help

The run asks one confirm at the start, then proceeds automatically. It reboots once at step 6 and
auto-resumes on return (login) via a one-shot GUI autostart entry — no manual re-run needed (GUI session
required; one sudo password after return). If the autostart cannot register, re-run 'bash install.sh' after
reboot to continue. Completed steps are auto-skipped on any re-run.

The cobot2 application (DSR driver + RealSense + host voice Python + workspace build + containers) is set up
separately by setup-app.sh after this base install — this repo does not ship the cobot2 source
(place it yourself; setup-app.sh verifies it is present).

By default the console shows only the [n/total] progress + per-step elapsed time; ALL detailed output and
any warnings/errors go to install_log in the repo root (not the console). On a step failure a one-line
[FAIL] + the log path is shown. Use --verbose or the VERBOSE=1 environment variable to also show detailed
output on the console.
EOF
}

# --verbose / --no-nvidia-driver = 서브커맨드 아님, 모든 서브커맨드에 붙는 modifier
VERBOSE="${VERBOSE:-0}"
NO_NVIDIA_DRIVER=0
__args=()
for __a in "$@"; do
    case "$__a" in
        -v|--verbose) VERBOSE=1 ;;
        --no-nvidia-driver) NO_NVIDIA_DRIVER=1 ;;
        *) __args+=("$__a") ;;
    esac
done
export VERBOSE
# "${__args[@]}" 로 축약 → 인자 없이 실행 시 bash 4.4 미만에서 unbound 에러
set -- "${__args[@]+"${__args[@]}"}"

# --- 인자 처리 ---
case "${1:-}" in
    --status) state_dump; exit 0 ;;
    --reset)
        confirm_or_abort "Reset the state file? (re-runs all steps on reinstall)"
        rm -f "$STATE_FILE"
        echo "install: state reset complete (deleted $STATE_FILE)."
        exit 0
        ;;
    --resume-terminal)
        # 재부팅 뒤 GUI autostart 전용 내부 플래그(도움말 미노출)
        cd "${SCRIPT_DIR}"
        rc=0; bash "$0" || rc=$?
        echo
        echo "[resume] install.sh exited (${rc}). Keeping this terminal open so you can review the result."
        # 터미널 입력 상태 복원
        stty sane 2>/dev/null || true
        exec bash
        ;;
    --help|-h) usage; exit 0 ;;
    "") : ;;
    *) echo "install: unknown option '$1'" >&2; usage; exit 2 ;;
esac

# 로그 디렉토리 선생성
mkdir -p "$(dirname "$LOG_FILE")"

# 배너 출력 조건 = 실제 설치일 때만
print_copyright

# --- 사전 점검: 대상 OS 확인 ---
if [[ ! -f /etc/os-release ]]; then
    echo "install: cannot read /etc/os-release — make sure this is an Ubuntu environment." >&2
    exit 1
fi
# shellcheck source=/dev/null
host_codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
if [[ "$host_codename" != "$UBUNTU_CODENAME" ]]; then
    echo "install: this installer targets Ubuntu '$UBUNTU_CODENAME' (current: '${host_codename:-unknown}')." >&2
    exit 1
fi
# sudo 비밀번호 = 단계 시작 전 1회 수령
sudo_prime install

# run_step 바깥 실패의 위치 통지
trap 'echo "[install] failed: line $LINENO — see ${LOG_FILE}" >&2' ERR

# --- 시작 confirm 1회 + 재부팅 뒤 자동 재개 등록 ---
# 첫 실행 = confirm 1회 + autostart 등록 / 재개된 실행 = 그 autostart 삭제
if step_should_skip a01_reboot; then
    remove_resume_autostart
elif [[ -t 0 ]]; then
    confirm_or_abort "The install reboots once midway and auto-continues on return (login) (terminal auto-opens, one sudo password). Continue?"
    register_resume_autostart "${SCRIPT_DIR}"
else
    # 참고 경고 = 콘솔 아님, 로그 전용
    { echo "[install] warning: non-interactive shell — cannot register auto-resume."
      echo "          Run it in a GUI session, or re-run 'bash install.sh' manually after reboot."; } >>"$LOG_FILE"
fi

# --- 단계 1~5: 커널 기준선 / NVIDIA / Docker / ROS2 / 추가 도구 ---
# 순서 = 커널 먼저, NVIDIA 나중
run_stage_a01 0 "$NO_NVIDIA_DRIVER"

# --- 단계 6: 재부팅 경계 ---
# run_step 미사용(reboot = 프로세스 종료)
# 재부팅 전 DONE 디스크 기록 → 복귀 후 이 단계 skip
if ! step_should_skip a01_reboot; then
    step_begin 6 "${STEPS_TOTAL}" a01_reboot
    # 재부팅 동의 = 시작 confirm 에서 수령 완료
    echo "[install] prerequisites (kernel/driver/Docker/ROS2) complete — rebooting to apply the driver and docker group."
    step_end DONE
    echo
    echo ">>> Rebooting. It auto-resumes on return (login) — no manual run needed."
    sudo reboot
fi

# 재부팅 직후 점검 = 부팅된 커널의 wifi / USB 입력 드라이버 모듈 포함 여부
__running="$(uname -r)"
if [[ ! -d "/lib/modules/${__running}/kernel/drivers/net/wireless" ]]; then
    { echo "[install] warning: the current kernel (${__running}) appears to lack its extra modules — wifi/USB input may be missing."
      echo "          Reboot into a kernel that has them (GRUB > Advanced options), then run this installer again."
      echo "          Check with: ls /lib/modules/\$(uname -r)/kernel/drivers/net/wireless"; } \
        | tee -a "$LOG_FILE" >&2 || true
fi

# --- 단계 7: VS Code ---
run_stage_a03 6

# --- 단계 8: DDS 튜닝(CycloneDDS 소켓 버퍼 + 유선 NIC 화이트리스트) ---
# 단독 실행: bash resources/hostcfg.sh dds
run_step 8 dds_tuning bash "${RESOURCE_DIR}/hostcfg.sh" dds

# --- 단계 9: 정적 이더넷 IP(로봇 LAN: .1 그리퍼 / .100 로봇 / .30 host) ---
# nmcli 로 유선 NIC 에 고정 IP 부여
# gateway/DNS 공란 → 인터넷 경로는 계속 wifi
run_step 9 network_static_ip bash "${RESOURCE_DIR}/hostcfg.sh" network

# 자동 재개 항목 정리
remove_resume_autostart 2>/dev/null || true

state_dump
echo "install: all 9 steps complete — base host environment ready."
echo "  next:"
echo "    1) place the cobot2 source at ${DSR_WORKSPACE}/src/cobot2"
echo "    2) run 'bash setup-app.sh' (workspace + containers)"
echo "  detailed log: ${LOG_FILE}"
