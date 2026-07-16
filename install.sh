#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# install.sh — 호스트 워크스테이션의 base 환경을 설치하는 단일 진입점(entry point).
#
# base 환경만 설치(커널/NVIDIA/Docker/ROS2 + reboot + VS Code + DDS 튜닝 + 정적
# 네트워크 IP). 전부 하나의 연속 시퀀스([n/9])로 실행. cobot2 앱 계층
# (DSR 드라이버 + RealSense + cobot2 colcon 빌드 + host voice Python + 컨테이너 toolkit/이미지)은
# 여기 없음 — setup-app.sh 에 있고, base 설치 후 실행. 이 레포는 cobot2 소스·corecode 미포함
# (둘 다 사용자가 별도로 배치).
# 재실행 안전: state 파일 기준 — 이미 끝난 단계 자동 건너뜀 + 멈춘 지점부터 이어서 진행.
# 특정 작업만 강제 재실행 = --reset(전체 초기화) 또는 resources/<step>.sh 직접 실행.
#
# 사용법:
#   bash install.sh            전체 시퀀스 실행(이미 끝난 단계는 건너뜀)
#   bash install.sh --status   현재 진행 상황(state) 출력
#   bash install.sh --reset    state 초기화(confirm 후 — 모든 단계 다시 실행)
#   bash install.sh --help
#
# 드라이버/docker 그룹 적용 위해 step 6 에서 한 번 reboot. 복귀(로그인) 후에는
# 일회성 GUI autostart 항목으로 자동 재개(resume) — 수동 재실행 불필요(GUI 세션 가정). autostart
# 등록 불가 시(터미널 에뮬레이터 없음) reboot 후 'bash install.sh' 재실행 → step 7 부터 이어감.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="${SCRIPT_DIR}/resources"

# root 로 직접 실행 금지 — HOME=/root 가 되면 state / docker 그룹 / 워크스페이스가 실수로 /root
# 아래에 생겨 일반 사용자 환경에 전혀 미반영. 하위 스크립트가 필요한 명령을 알아서 sudo 로 호출.
if [[ "$(id -u)" -eq 0 ]]; then
    echo "install: do not run with sudo. Run 'bash install.sh' as a regular user." >&2
    echo "         (the script calls the necessary commands via sudo on its own.)" >&2
    exit 1
fi

# 단계 엔진(state + run_step + 단계 정의) + 설치 UX(confirm + env 로드 + 자동 재개).
# shellcheck source=resources/config.sh
source "${RESOURCE_DIR}/config.sh"
# shellcheck source=resources/orchestrate.sh
source "${RESOURCE_DIR}/orchestrate.sh"
# shellcheck source=resources/interaction.sh
source "${RESOURCE_DIR}/interaction.sh"
config_assert_set
STEPS_TOTAL="$(install_steps_total)"

usage() {
    cat <<'EOF'
install.sh — single entry point for the BASE host environment (kernel/NVIDIA/Docker/ROS2 + reboot + VS Code + DDS tuning + static network IP, 9 steps total)

  bash install.sh             run the full sequence (skip already-completed steps)
  bash install.sh --verbose   also show each step's detailed output + warnings/errors on the console
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

# 프로젝트 저작권 배너 — 실제 설치 실행 때마다 콘솔에 출력. step 6 reboot 이후 자동 재개된
# 터미널에서도 출력되므로 저작권 표기 항상 노출. 무조건 stdout 으로 나감. 단계별 출력이 아니라서
# 로그 라우팅/조용한 콘솔 규칙(진행률만 표시) 여기엔 미적용.
print_copyright() {
    cat <<'EOF'
============================================================
 Cobot2 Jazzy Installer
 Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
============================================================
EOF
}

# --verbose/-v 는 서브커맨드와 직교(independent — 서로 영향 없음) → 먼저 VERBOSE 로 분리, 나머지 인자만 남김.
# orchestrate.sh 의 run_step 은 같은 셸에서 VERBOSE 를 읽음(export 는 하위 resource 스크립트용).
VERBOSE="${VERBOSE:-0}"
__args=()
for __a in "$@"; do
    case "$__a" in
        -v|--verbose) VERBOSE=1 ;;
        *) __args+=("$__a") ;;
    esac
done
export VERBOSE
# 빈 배열 + set -u 조합에서 나는 unbound-var(정의 안 된 변수) 에러(bash<4.4)를 막는 확장 가드. "${__args[@]}" 로 단순화 금지.
set -- "${__args[@]+"${__args[@]}"}"

# --- 인자 처리(argument dispatch) (set -u 에서는 ${1:-} 필요) ---
case "${1:-}" in
    --status) state_dump; exit 0 ;;
    --reset)
        confirm_or_abort "Reset the state file? (re-runs all steps on reinstall)"
        rm -f "$STATE_FILE"
        echo "install: state reset complete (deleted $STATE_FILE)."
        exit 0
        ;;
    --help|-h) usage; exit 0 ;;
    "") : ;;
    *) echo "install: unknown option '$1'" >&2; usage; exit 2 ;;
esac

# $LOG_FILE 에 뭔가 쓰기 전에(아래 참고 경고 / ERR trap) 상세 로그 디렉토리 존재를 먼저 보장.
# 그래야 LOG_FILE 을 아직 없는 디렉토리로 바꿔 지정해도 이런 초기 기록이 조용히 사라지지 않음.
# 기본 경로(레포 루트 / install_log)면 dirname 이 레포 루트라, 이 명령은 아무 일도 안 하는 무해한 no-op.
mkdir -p "$(dirname "$LOG_FILE")"

# 실제 설치 실행에서 저작권 배너 출력(위 유틸리티 서브커맨드는 이미 exit 한 뒤).
# 무조건 실행 → 첫 실행에서도, reboot 후 자동 재개된 터미널에서도 똑같이 보임.
print_copyright

# --- 사전 점검(preflight): 잘못된 환경에서 절반쯤 실행되다 실패하는 사고 사전 방지 ---
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
# sudo 비밀번호 처음에 한 번 받고 keepalive 시작(60초마다 캐시 갱신 → 긴 단계나 자동 재개
# 흐름에서 다시 안 묻게 함). resources/interaction.sh 를 통해 setup-app.sh 와 공유.
sudo_prime install

# 하위 본문 안에서 예상치 못한 실패가 난 위치를 확실히 알림(run_step 의 step_end_fail 과는 별개).
# 콘솔엔 한 줄 알림 + 로그 경로만 — 실패 상세는 로그에(콘솔은 깔끔하게 유지).
trap 'echo "[install] failed: line $LINENO — see ${LOG_FILE}" >&2' ERR

# --- proceed-confirm 1회 + step 6 reboot 를 건너뛰는 자동 재개 등록 ----------------------------
# 첫 실행(reboot 전): proceed-confirm 1회 + 복귀 시 자동 재개 등록. 여기 confirm 은 reboot 동의만 의미.
# 재개(reboot 후): autostart 항목 즉시 제거(일회성 — 매 로그인마다 다시 뜨는 것 방지). sudo 는 위 sudo -v 로
#   이 터미널에서 한 번 입력됨.
if step_should_skip a01_reboot; then
    remove_resume_autostart
elif [[ -t 0 ]]; then
    confirm_or_abort "The install reboots once midway and auto-continues on return (login) (terminal auto-opens, one sudo password). Continue?"
    register_resume_autostart "${SCRIPT_DIR}"
else
    # 참고 경고 → 로그에만 기록(콘솔은 깔끔하게 유지). 진단용으로 install_log 에 남음.
    { echo "[install] warning: non-interactive shell — cannot register auto-resume."
      echo "          Run it in a GUI session, or re-run 'bash install.sh' manually after reboot."; } >>"$LOG_FILE"
fi

# --- step 1~5: 사전 준비물(a01: 커널 기준선 / NVIDIA / Docker / ROS2 jazzy / 추가 도구) ---
# nvidia 보다 커널 기준선을 먼저: HWE 커널(Ubuntu 하드웨어 지원 커널) 메타 + 헤더 + modules-extra 를 먼저
# 보장 필요. 그래야 벽돌화(nvidia 모듈이 반쪽짜리 커널을 끌어오는 것)와 DKMS 헤더 누락을 둘 다 방지.
run_stage_a01 0

# --- step 6: reboot 경계(a01) ---
# run_step 으로 감쌀 수 없음: reboot 는 프로세스를 끝내버리고, 이후 단계(7 이후)는 모두 reboot 뒤에
# 실행돼야 함. reboot 전에 DONE 을 디스크에 기록 → reboot 후 재실행이 이 단계를 건너뛰게 함
# (무한 reboot 루프 방지).
# confirm 거절 / 비대화 중단 시엔 DONE 미기록 → a01_reboot 은 RUNNING 상태로 남음.
# 건너뛰기 판단은 DONE 만 보므로, 다음 실행에서 reboot 를 다시 물음 — 아직 동의를 안 받았으니 의도된 동작.
if ! step_should_skip a01_reboot; then
    step_begin 6 "${STEPS_TOTAL}" a01_reboot
    # reboot 동의는 위의 시작 confirm 에서 이미 받음(tty 실행) — 다시 안 물음. 비대화 첫 실행은
    # 그 confirm 을 경고를 로그에 남기고 건너뛴 뒤, 여기서 자동으로 진행.
    echo "[install] prerequisites (kernel/driver/Docker/ROS2) complete — rebooting to apply the driver and docker group."
    step_end_ok
    echo
    echo ">>> Rebooting. It auto-resumes on return (login) — no manual run needed."
    sudo reboot
fi

# reboot 복귀 직후 조기 점검: 부팅된 커널에 wifi/USB 드라이버(modules-extra) 존재 여부 확인.
# 잘못된(반쪽) 커널로 부팅됐다면, 이후 단계(RealSense DKMS 등)로 넘어가기 전에 경고.
__running="$(uname -r)"
if [[ ! -d "/lib/modules/${__running}/kernel/drivers/net/wireless" ]]; then
    # 참고 경고 → 로그에만 기록(콘솔은 깔끔하게 유지). 진단용으로 install_log 에 남음.
    { echo "[install] warning: the current kernel (${__running}) appears to lack modules-extra — wifi/USB input may be missing."
      echo "          Boot a kernel that has modules-extra from GRUB, or see the kernel-module section in docs/TROUBLESHOOTING.md."; } >>"$LOG_FILE"
fi

# 참고: 앱 계층(DSR 드라이버 + RealSense + cobot2 colcon 빌드 + 컨테이너 toolkit/이미지)은 더 이상
# install.sh 에 없음 — setup-app.sh 로 옮겼고, base 설치 후 실행.

# --- step 7: 개발 도구(a03: VS Code) ---
run_stage_a03 6

# --- step 8: DDS 튜닝(CycloneDDS 버퍼 + 유선 NIC 자동 화이트리스트) ---
# 호스트 노드와 앱 컨테이너가 함께 쓰는 cyclonedds 환경을 결정론적으로(항상 같은 결과) 설정.
# 스테이지 스크립트에 없음 — install.sh 에서만, 또는 단독(bash resources/dds-tuning.sh)으로 실행.
run_step 8 dds_tuning bash "${RESOURCE_DIR}/dds-tuning.sh"

# --- step 9: 정적 이더넷 IP(로봇 LAN: .1 그리퍼 / .100 로봇 / .30 호스트) ---
# 유선 NIC 을 로봇 LAN 정적 IP 로 설정(nmcli). gateway/DNS 없음 → wifi 인터넷은 그대로. 멱등(여러 번 실행해도 결과 동일).
# confirm 없음(되돌릴 수 있고, 실행 시작의 단일 동의가 이걸 포함).
run_step 9 network_static_ip bash "${RESOURCE_DIR}/network-static-ip.sh"

# 재개용 autostart 정리(재개 진입 때 이미 제거됐으면 아무 일 안 함 — 멱등).
remove_resume_autostart 2>/dev/null || true

state_dump
echo "install: all 9 steps complete — base host environment ready."
echo "  next:"
echo "    1) place the cobot2 source at ${DSR_WORKSPACE}/src/cobot2"
echo "    2) run 'bash setup-app.sh' (workspace + containers)"
echo "  detailed log: ${LOG_FILE}"
