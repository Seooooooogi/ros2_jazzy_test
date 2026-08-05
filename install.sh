#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# install.sh — host 워크스테이션의 base 환경을 설치하는 단일 진입점.
#
# 커널 / NVIDIA / Docker / ROS2 → reboot → VS Code → DDS 튜닝 → 정적 IP 까지 9 단계.
# cobot2 앱 계층(DSR 드라이버 / RealSense / colcon 빌드 / host voice / 컨테이너)은 여기 없다 —
# base 설치가 끝난 뒤 setup-app.sh 가 올린다. cobot2 소스와 corecode 는 사용자가 직접 배치한다.
# 몇 번을 다시 실행해도 안전하다 — 끝난 단계는 state 파일을 보고 건너뛰고 멈춘 지점부터 이어간다.
# 한 단계만 다시 돌리려면 --reset(전체 초기화)하거나 resources/{base-install,hostcfg}.sh 의 해당
# 서브커맨드를 직접 실행한다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="${SCRIPT_DIR}/resources"

# root 로 실행하면 HOME=/root 가 되어 state · docker 그룹 · 워크스페이스가 전부 /root 아래에 생기고
# 정작 쓸 사용자 계정에는 아무것도 반영되지 않는다. 필요한 명령은 하위 스크립트가 알아서 sudo 로 부른다.
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

# --verbose 와 --no-nvidia-driver 는 서브커맨드가 아니라 어느 서브커맨드에나 붙는 modifier 다.
# 여기서 먼저 걷어내야 아래 case 가 --status / --reset / 빈 인자만 보고 판단할 수 있다.
# run_step 은 같은 셸에서 VERBOSE 를 읽고, export 는 하위 resources 스크립트를 위한 것.
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
# "${__args[@]}" 로 줄이면 인자 없이 실행할 때 bash 4.4 미만에서 unbound 에러가 난다.
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
        # 재부팅 뒤 GUI autostart 가 부르는 내부 플래그 — 사람이 칠 일이 없어 도움말에 없다.
        # 설치를 다시 돌린 뒤 결과를 볼 수 있도록 터미널을 닫지 않고 열어 둔다.
        cd "${SCRIPT_DIR}"
        rc=0; bash "$0" || rc=$?
        echo
        echo "[resume] install.sh exited (${rc}). Keeping this terminal open so you can review the result."
        # heartbeat 나 비밀번호 입력이 터미널 입력 상태를 흐트러뜨렸을 수 있어 되돌린다.
        stty sane 2>/dev/null || true
        exec bash
        ;;
    --help|-h) usage; exit 0 ;;
    "") : ;;
    *) echo "install: unknown option '$1'" >&2; usage; exit 2 ;;
esac

# 로그 디렉토리를 먼저 만든다 — 아래 경고와 ERR trap 이 LOG_FILE 에 쓰는데, LOG_FILE 을 아직 없는
# 디렉토리로 바꿔 지정한 경우 그 초기 기록이 조용히 사라진다. 기본 경로에서는 아무 일도 하지 않는다.
mkdir -p "$(dirname "$LOG_FILE")"

# 실제 설치일 때만 배너(위 유틸리티 서브커맨드는 이미 exit 했다). 자동 재개된 터미널에서도 똑같이 보인다.
print_copyright

# --- 사전 점검 — 엉뚱한 환경에서 절반쯤 깔리다 실패하는 사고를 막는다 ---
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
# sudo 비밀번호는 단계가 시작되기 전에 한 번만 받는다 — 단계 도중에 물으면 그 프롬프트가 heartbeat
# 줄에 가려, 비밀번호를 다 치기도 전에 설치가 진행되는 것처럼 보인다.
sudo_prime install

# run_step 바깥에서 난 실패의 위치를 알린다(단계 안의 실패는 run_step 의 step_end FAIL 이 처리).
# 콘솔에는 한 줄과 로그 경로만 남기고 상세는 로그로 보낸다.
trap 'echo "[install] failed: line $LINENO — see ${LOG_FILE}" >&2' ERR

# --- 시작 confirm 1회 + 재부팅 뒤 자동 재개 등록 ---
# 첫 실행: confirm 을 한 번 받고(= 단계 6 의 재부팅 동의) 복귀용 autostart 를 등록한다.
# 재개된 실행: 그 autostart 를 곧바로 지운다 — 일회성이라 로그인할 때마다 다시 뜨면 안 된다.
if step_should_skip a01_reboot; then
    remove_resume_autostart
elif [[ -t 0 ]]; then
    confirm_or_abort "The install reboots once midway and auto-continues on return (login) (terminal auto-opens, one sudo password). Continue?"
    register_resume_autostart "${SCRIPT_DIR}"
else
    # 참고 경고는 콘솔이 아니라 로그에만 남긴다.
    { echo "[install] warning: non-interactive shell — cannot register auto-resume."
      echo "          Run it in a GUI session, or re-run 'bash install.sh' manually after reboot."; } >>"$LOG_FILE"
fi

# --- 단계 1~5: 커널 기준선 / NVIDIA / Docker / ROS2 / 추가 도구 ---
# 커널을 NVIDIA 보다 먼저 세운다 — HWE 커널(최신 하드웨어 지원을 얹은 Ubuntu 커널 트랙) 메타 +
# 헤더 + modules-extra 가 먼저 깔려 있어야 드라이버 모듈이 반쪽짜리 커널에 붙는 사고와
# DKMS(커널이 바뀔 때마다 모듈을 자동 재빌드하는 구조) 헤더 누락을 둘 다 피한다.
run_stage_a01 0 "$NO_NVIDIA_DRIVER"

# --- 단계 6: 재부팅 경계 ---
# run_step 으로 감싸지 않는다 — reboot 은 프로세스를 끝내 버려 단계 실행 틀에 맞지 않고, 7 단계부터는
# 전부 재부팅 뒤에 돌아야 한다. 재부팅 전에 DONE 을 디스크에 기록해야 복귀 후 실행이 이 단계를
# 건너뛴다(안 그러면 재부팅 무한 루프). 중단돼 DONE 이 안 남으면 다음 실행에서 다시 묻는데,
# 아직 동의를 못 받은 것이므로 의도한 동작이다.
if ! step_should_skip a01_reboot; then
    step_begin 6 "${STEPS_TOTAL}" a01_reboot
    # 재부팅 동의는 위의 시작 confirm 에서 이미 받았다 — 여기서 다시 묻지 않는다.
    echo "[install] prerequisites (kernel/driver/Docker/ROS2) complete — rebooting to apply the driver and docker group."
    step_end DONE
    echo
    echo ">>> Rebooting. It auto-resumes on return (login) — no manual run needed."
    sudo reboot
fi

# 재부팅 직후 점검 — 부팅된 커널에 wifi / USB 입력 드라이버 모듈이 들어 있는지 본다.
# 재부팅 전과 달리 여기서 없으면 "새 커널을 아직 안 탔을 뿐" 이 아니라 진짜 반쪽 커널이다.
# 콘솔에도 띄운다 — 로그에만 남기면 아무도 안 보는데, 이 경고가 사실상 유일한 안전망이다.
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
# host 노드와 앱 컨테이너가 같은 설정을 보게 맞춘다. 따로 돌리려면 bash resources/hostcfg.sh dds.
run_step 8 dds_tuning bash "${RESOURCE_DIR}/hostcfg.sh" dds

# --- 단계 9: 정적 이더넷 IP(로봇 LAN: .1 그리퍼 / .100 로봇 / .30 host) ---
# nmcli 로 유선 NIC 에 고정 IP 를 준다. gateway/DNS 를 비워 인터넷은 계속 wifi 로 나간다.
# 되돌릴 수 있는 설정이라 여기서 따로 묻지 않는다(시작 confirm 에 포함).
run_step 9 network_static_ip bash "${RESOURCE_DIR}/hostcfg.sh" network

# 자동 재개 항목 정리 — 재개로 들어올 때 이미 지웠으면 아무 일도 하지 않는다.
remove_resume_autostart 2>/dev/null || true

state_dump
echo "install: all 9 steps complete — base host environment ready."
echo "  next:"
echo "    1) place the cobot2 source at ${DSR_WORKSPACE}/src/cobot2"
echo "    2) run 'bash setup-app.sh' (workspace + containers)"
echo "  detailed log: ${LOG_FILE}"
