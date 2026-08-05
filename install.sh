#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# install.sh · host 워크스테이션 base 환경 설치의 단일 진입점
#
# 9 단계 = 커널 / NVIDIA / Docker / ROS2 → reboot → VS Code → DDS 튜닝 → 정적 IP
# cobot2 앱 계층(DSR 드라이버 / RealSense / colcon 빌드 / host voice / 컨테이너) = 여기 미포함
#   담당 = base 설치 후의 setup-app.sh
#   cobot2 소스 + corecode = 사용자가 직접 배치
# 재실행 안전(N회 무해)
#   완료 단계 = state 파일 기준 skip → 중단 지점부터 재개
# 한 단계만 재실행하려면
#   --reset(전체 초기화)
#   또는 resources/{base-install,hostcfg}.sh 의 해당 서브커맨드 직접 실행
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="${SCRIPT_DIR}/resources"

# root 실행 → HOME=/root
#   state · docker 그룹 · 워크스페이스가 전부 /root 아래 생성
#   → 실제 사용할 사용자 계정에 무반영
# 필요한 명령 = 하위 스크립트가 자체적으로 sudo 호출
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
#   선분리 필요 → 아래 case 가 --status / --reset / 빈 인자만 보고 판단 가능
# VERBOSE 소비처
#   run_step = 같은 셸에서 직접 읽음
#   export = 하위 resources 스크립트용
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
        # 재부팅 뒤 GUI autostart 전용 내부 플래그(사람이 직접 입력할 일 없음 → 도움말 미노출)
        # 설치 재실행 후 결과 확인용 → 터미널 미종료 상태로 유지
        cd "${SCRIPT_DIR}"
        rc=0; bash "$0" || rc=$?
        echo
        echo "[resume] install.sh exited (${rc}). Keeping this terminal open so you can review the result."
        # heartbeat / 비밀번호 입력이 터미널 입력 상태를 훼손했을 가능성 → 복원
        stty sane 2>/dev/null || true
        exec bash
        ;;
    --help|-h) usage; exit 0 ;;
    "") : ;;
    *) echo "install: unknown option '$1'" >&2; usage; exit 2 ;;
esac

# 로그 디렉토리 선생성
#   아래 경고 + ERR trap = LOG_FILE 에 기록
#   LOG_FILE 을 미존재 디렉토리로 지정한 경우 → 그 초기 기록이 조용히 소실
#   기본 경로 = 무동작
mkdir -p "$(dirname "$LOG_FILE")"

# 배너 출력 조건 = 실제 설치일 때만(위 유틸리티 서브커맨드 = 이미 exit)
#   자동 재개된 터미널에서도 동일 출력
print_copyright

# --- 사전 점검: 엉뚱한 환경에서 절반쯤 설치되다 실패하는 사고 차단 ---
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
#   단계 도중 질문 → 프롬프트가 heartbeat 줄에 가림
#   → 비밀번호 입력 완료 전에 설치가 진행되는 것처럼 보임
sudo_prime install

# run_step 바깥 실패의 위치 통지(단계 안의 실패 = run_step 의 step_end FAIL 담당)
# 콘솔 = 한 줄 + 로그 경로 / 상세 = 로그행
trap 'echo "[install] failed: line $LINENO — see ${LOG_FILE}" >&2' ERR

# --- 시작 confirm 1회 + 재부팅 뒤 자동 재개 등록 ---
# 첫 실행 = confirm 1회 수령(= 단계 6 의 재부팅 동의) + 복귀용 autostart 등록
# 재개된 실행 = 그 autostart 즉시 삭제(일회성 → 로그인할 때마다 재등장 금지)
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
#   HWE 커널 = 최신 하드웨어 지원을 얹은 Ubuntu 커널 트랙
#   HWE 메타 + 헤더 + modules-extra 선설치 필요
#   → 드라이버 모듈이 반쪽 커널에 붙는 사고 회피
#   → DKMS 헤더 누락 회피
#   DKMS = 커널 교체 시마다 모듈을 자동 재빌드하는 구조
run_stage_a01 0 "$NO_NVIDIA_DRIVER"

# --- 단계 6: 재부팅 경계 ---
# run_step 미사용
#   reboot = 프로세스 종료 → 단계 실행 틀에 부적합
#   7 단계 이후 = 전부 재부팅 뒤 실행 대상
# 재부팅 전 DONE 디스크 기록 필수
#   → 복귀 후 실행이 이 단계 skip
#   미기록 시 재부팅 무한 루프
# 중단으로 DONE 미기록 → 다음 실행에서 재질문(아직 동의 미수령 상태 → 의도된 동작)
if ! step_should_skip a01_reboot; then
    step_begin 6 "${STEPS_TOTAL}" a01_reboot
    # 재부팅 동의 = 위의 시작 confirm 에서 수령 완료 → 여기서 재질문 없음
    echo "[install] prerequisites (kernel/driver/Docker/ROS2) complete — rebooting to apply the driver and docker group."
    step_end DONE
    echo
    echo ">>> Rebooting. It auto-resumes on return (login) — no manual run needed."
    sudo reboot
fi

# 재부팅 직후 점검 = 부팅된 커널의 wifi / USB 입력 드라이버 모듈 포함 여부(재부팅 전과 차이: 여기서 부재 = "새 커널 미적용" 아님, 실제 반쪽 커널)
# 출력 대상 = 콘솔에도
#   로그 전용 → 아무도 확인 안 함
#   이 경고 = 사실상 유일한 안전망
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
# 목적 = host 노드 + 앱 컨테이너가 같은 설정 참조
# 단독 실행: bash resources/hostcfg.sh dds
run_step 8 dds_tuning bash "${RESOURCE_DIR}/hostcfg.sh" dds

# --- 단계 9: 정적 이더넷 IP(로봇 LAN: .1 그리퍼 / .100 로봇 / .30 host) ---
# nmcli 로 유선 NIC 에 고정 IP 부여
# gateway/DNS 공란 → 인터넷 경로는 계속 wifi
# 가역 설정 → 여기서 별도 질문 없음(시작 confirm 에 포함)
run_step 9 network_static_ip bash "${RESOURCE_DIR}/hostcfg.sh" network

# 자동 재개 항목 정리(재개 진입 시 이미 삭제 → 무동작)
remove_resume_autostart 2>/dev/null || true

state_dump
echo "install: all 9 steps complete — base host environment ready."
echo "  next:"
echo "    1) place the cobot2 source at ${DSR_WORKSPACE}/src/cobot2"
echo "    2) run 'bash setup-app.sh' (workspace + containers)"
echo "  detailed log: ${LOG_FILE}"
