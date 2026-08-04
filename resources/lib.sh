#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck shell=bash
# resources/lib.sh — 설치 단계 엔진 + 설치 UX 헬퍼 + apt 저장소 등록을 묶은 source 전용 라이브러리.
# source 전용 라이브러리 — set -euo 를 여기 두지 않는다(호출 진입점이 셸 옵션을 소유).
#
# 네 그룹을 한 파일에 묶음 — 늘 함께 source 되어 나눠 둘 이유가 없었음:
#   1) state       — 단계 진행 상태(DONE/FAIL/SKIPPED/RUNNING)를 state 파일에 멱등하게 기록(재개 + [n/total]).
#   2) run_step    — skip 판단 + begin/end + 로그 분리 + heartbeat 를 묶은 중앙 실행 래퍼.
#   3) steps       — install.sh 전체 시퀀스가 호출하는 단계 정의(stage 함수 + 분모 상수).
#   4) confirm     — 되돌릴 수 없는 작업(reboot / purge / 드라이버 교체) 전 명시적 동의.
#   5) resume      — 일회성 GUI autostart 등록/제거로 step-6 reboot 를 넘어 자동 재개.
#   6) sudo-prime  — sudo 비밀번호를 처음에 한 번만 받고 캐시를 유지.
#   7) add_apt_repo — apt 저장소·키링 등록을 멱등하게 처리.
#
# config.sh 가 먼저 source 되어 있어야 함(STATE_FILE / LOG_FILE / STATE_DIR / TOTAL_STEPS / KEYRING_DIR).
# 호출자가 RESOURCE_DIR 와 STEPS_TOTAL 을 설정. 함수는 호출 시점에 이름을 해석하므로 source 순서는 무관.

# ============================================================================
# 1) state — 단계 진행 상태 추적(재개 가능한 재실행 + [n/total] 진행률)
# ============================================================================
# state 파일 형식(key=value — grep/sed 기반 in-place 갱신으로 멱등하게 기록):
#   step_<name>=DONE|FAIL|SKIPPED|RUNNING
#
# 사용법(설치 단계에서 호출):
#   step_should_skip a01_prerequirements && return 0
#   step_begin 1 6 a01_prerequirements
#   ... 작업 수행 ...
#   step_end DONE     # 실패 시엔 step_end FAIL
#
# 멱등: 같은 단계를 RUNNING -> DONE 으로 여러 번 기록해도 state 파일에는 한 줄만 남음.
# 의존성: config.sh 의 STATE_FILE 가 정의돼 있어야 함.

# 내부 상태: 현재 실행 중인 단계 이름(step_begin -> step_end 짝 맞추기용).
__current_step=""

# 1 = 단계 결과를 state 파일에 남기고 완료된 단계는 건너뛴다(install.sh — 재부팅을 넘어 재개해야 함).
# 0 = 배너·로그·heartbeat 만 하고 state 는 안 건드린다(setup-app.sh — 재개 개념이 없다).
: "${STEP_STATE:=1}"

# state 파일 없으면 생성.
_state_ensure_file() {
    mkdir -p "$(dirname "$STATE_FILE")"
    [[ -f "$STATE_FILE" ]] || : > "$STATE_FILE"
}

#######################################
# state 파일의 step_<name> 줄을 status 로 설정(없으면 추가, 있으면 교체).
# Globals:
#   STATE_FILE (읽기/쓰기)
# Arguments:
#   $1 - 단계 이름 name
#   $2 - 상태 status (DONE/FAIL/SKIPPED/RUNNING)
#######################################
_state_set() {
    local name="$1" status="$2" key
    _state_ensure_file
    key="step_${name}"
    if grep -qE "^${key}=" "$STATE_FILE"; then
        sed -i "s|^${key}=.*|${key}=${status}|" "$STATE_FILE"
    else
        echo "${key}=${status}" >> "$STATE_FILE"
    fi
}

#######################################
# state 파일에서 step_<name> 의 현재 status 를 출력(없으면 빈 문자열).
# Globals:
#   STATE_FILE (읽기)
# Arguments:
#   $1 - 단계 이름 name
#######################################
_state_get() {
    local name="$1"
    _state_ensure_file
    sed -n "s|^step_${name}=||p" "$STATE_FILE" | tail -n1
}

#######################################
# 이 단계를 건너뛰어도 되는지 확인(DONE = 완료, SKIPPED = 의도적 opt-out).
# SKIPPED 도 인정해야 하는 이유: --no-nvidia-driver 로 SKIPPED 기록된 단계가
# step 6 reboot 후 인자 없는 재실행에서도 다시 돌지 않게 함(결정은 state 에만 남음).
# Globals:
#   STATE_FILE (읽기)
# Arguments:
#   $1 - 단계 이름 name
# Returns:
#   0 = 건너뛰어도 안전(DONE 또는 SKIPPED), 1 = 아직 미완료
#######################################
step_should_skip() {
    local name="$1"
    _state_ensure_file
    grep -qE "^step_${name}=(DONE|SKIPPED)$" "$STATE_FILE"
}

#######################################
# 단계 시작 — 진행률·헤더 출력 + state 에 RUNNING 기록.
# Globals:
#   __current_step (쓰기), STATE_FILE (쓰기)
# Arguments:
#   $1 - 단계 번호 n
#   $2 - 전체 단계 수 total
#   $3 - 단계 이름 name
# Outputs:
#   stdout 에 [n/total] 진행률 배너와 헤더
#######################################
step_begin() {
    local n="$1" total="$2" name="$3"
    __current_step="$name"
    _state_ensure_file
    echo
    echo "============================================================"
    echo "[${n}/${total}] step: ${name}"
    echo "============================================================"
    if [[ "${STEP_STATE}" == 1 ]]; then
        _state_set "${name}" RUNNING
    fi
}

# 현재 단계를 마무리하고 state 에 결과를 남긴다. status = DONE | FAIL | SKIPPED.
step_end() {
    local status="${1:-DONE}"
    if [[ -z "${__current_step}" ]]; then
        echo "state: step_end called without step_begin" >&2
        return 1
    fi
    [[ "${STEP_STATE}" == 1 ]] && _state_set "${__current_step}" "${status}"
    case "${status}" in
        DONE)    echo "[OK]  step ${__current_step} = DONE" ;;
        FAIL)    echo "[FAIL] step ${__current_step} = FAIL" >&2 ;;
        SKIPPED) echo "[SKIP] step ${__current_step} = SKIPPED" ;;
    esac
    __current_step=""
}

# 모든 단계 상태 출력(디버깅/검증용).
state_dump() {
    _state_ensure_file
    echo "--- state file: $STATE_FILE ---"
    cat "$STATE_FILE"
    echo "-------------------------------"
}

# ============================================================================
# 2) run_step — 단계 실행을 한곳에 모은 래퍼(오케스트레이션 정책)
# ============================================================================
# 위의 state 섹션(step_should_skip / step_begin / step_end_*)과 config.sh(TOTAL_STEPS)에 의존.
#
# 진행률 분모(total)는 호출 시점에 호출자가 설정한 STEPS_TOTAL 을 읽음.
# install.sh 가 STEPS_TOTAL(전체 단계 수, install_steps_total)을 설정.
# 설정돼 있지 않으면 config.sh 의 TOTAL_STEPS 로 대체(fallback).
#
# 상태 기록/조회는 위 state 섹션 담당, 이 섹션은 skip 판단 + begin/end 호출만 묶음.
#
# 출력 정책(비상세 모드 = 기본값): 단계 명령("$@")의 stdout 과 stderr 를 둘 다 config.sh 의 LOG_FILE
# 로만 보냄 — 콘솔은 깔끔하게 유지(step_begin/step_end_* 의 진행률 배너 + 살아있음을 보여주는
# heartbeat 만). 단계의 경고/에러는 콘솔에 안 나오고 로그에만 남음. 그래도 실패는 절대 조용히
# 넘어가지 않음: step_end_fail 이 [FAIL] 한 줄 + 로그 경로를 출력. (VERBOSE=1 이면 stdout+stderr 를
# 콘솔과 로그 양쪽에 tee 로 복제.) fd(파일 디스크립터) 처리 방식은 run_step 안의 라우팅 주석 참고.
#
# 실패 시 step_end_fail 로 FAIL 을 기록한 뒤 곧바로 exit 1 로 종료 — 이 경로에서는
# 호출자가 걸어둔 ERR trap 이 발동하지 않음(exit 는 trap 대상 아님). 그래서 실패 보고는
# step_end_fail 의 FAIL 기록이 유일한 진실 원천이고, ERR trap 은 run_step 바깥의 명령 실패만 잡음.

#######################################
# 경과 시간을 제자리(\r)로 갱신하는 heartbeat. 단계 진행 중 콘솔이 "멈춘 것"처럼 보이지 않게 함.
# 비상세 모드(stdout 은 로그로 감) + 대화형 터미널(tty)일 때만 표시. VERBOSE 모드에서는 단계의
# 실제 출력(colcon n/total, apt %)이 콘솔로 흐르므로 heartbeat 를 띄우지 않음.
# 첫 출력을 2초 늦춤: 단계 초반의 짧은 작업이나 sudo 비밀번호 프롬프트와 heartbeat 줄이 겹치지
# 않게 하려는 것 — sudo 는 보통 단계 시작 직후 물어보고 그 안에서 끝남.
# Arguments:
#   $1 - 단계 이름 name (heartbeat 줄에 표시)
# Outputs:
#   stderr 에 경과 시간을 \r 로 제자리 갱신
#######################################
_step_heartbeat() {
    local name="$1" start="$SECONDS" e
    while :; do
        sleep 2
        e=$(( SECONDS - start ))
        printf '\r  ⋯ %s running (%02d:%02d elapsed)\033[K' "$name" $(( e / 60 )) $(( e % 60 )) >&2
    done
}

#######################################
# 한 단계 실행: 이미 DONE 이면 건너뛰고, 아니면 begin → 실행 → ok/fail.
# Globals:
#   STEPS_TOTAL / TOTAL_STEPS (읽기), LOG_FILE / STATE_DIR (읽기), VERBOSE (읽기)
# Arguments:
#   [--interactive] - 단계가 stdin 으로 사용자 입력을 받을 때(예: API 키 직접 입력) heartbeat 를 끔.
#                     heartbeat 의 \r 갱신이 입력 프롬프트를 덮어써 입력이 깨지는 것을 막음.
#   $1 - 단계 번호 n
#   $2 - 단계 이름 name
#   $3.. - 실행할 명령 cmd...
# Outputs:
#   콘솔에 진행률 배너(+비상세·tty 면 heartbeat). 명령 출력은 로그로. 실패 시 [FAIL] + 로그 경로.
# Returns:
#   명령 없이 호출되면 exit 2, 단계 명령 실패 시 exit 1(함수 반환이 아니라 프로세스 종료)
#######################################
run_step() {
    local interactive=0
    if [[ "${1:-}" == --interactive ]]; then interactive=1; shift; fi
    local n="$1" name="$2"
    shift 2
    if [[ $# -eq 0 ]]; then
        echo "run-step: no command to run for '${name}' (run_step <n> <name> <cmd...>)." >&2
        exit 2
    fi
    local total="${STEPS_TOTAL:-${TOTAL_STEPS:?run-step: STEPS_TOTAL/TOTAL_STEPS not set}}"
    if [[ "${STEP_STATE}" == 1 ]] && step_should_skip "${name}"; then
        echo "[${n}/${total}] skip: ${name} (already $(_state_get "${name}" | tr '[:upper:]' '[:lower:]'))"
        return 0
    fi
    # 상세 설치 로그(config.sh 의 LOG_FILE)에 단계 구분 배너를 덧붙임. LOG_FILE 가 정의되지 않은
    # 환경(옛 source 순서)에서는 STATE_DIR 로 대체해 set -u 때문에 죽지 않게 함.
    local log="${LOG_FILE:-${STATE_DIR:?run-step: STATE_DIR not set}/install.log}"
    mkdir -p "$(dirname "$log")"
    { echo; echo "===== [${n}/${total}] ${name} — $(date '+%F %T') ====="; } >>"$log"

    step_begin "${n}" "${total}" "${name}"

    # 출력 라우팅:
    #   기본값(비상세): 명령의 stdout 과 stderr 를 둘 다 로그로만 보냄 — 콘솔은 깔끔하게 유지
    #     ([n/total] 배너 + 살아있음 heartbeat 만). 단계 경고/에러는 콘솔에 안 찍히고 로그에만 남음.
    #     그래도 실패는 조용하지 않음: 아래의 step_end_fail 이 [FAIL] 한 줄 + 로그 경로를 출력.
    #   VERBOSE=1: stdout+stderr 를 콘솔과 로그 양쪽에 실시간으로 tee(colcon [n/total], apt %).
    #
    # verbose tee 는 비동기 process-sub 라 명령이 끝난 뒤에도 아직 버퍼를 비우는 중일 수 있음. 열린 채로 두면
    # [OK]/[FAIL] 배너가 명령의 마지막 줄과 뒤섞일 수 있음. 그래서 exec 로 전용 fd 에 tee 를 열고,
    # 배너 전에 닫아서(EOF) 다 빠질 때까지 wait — 출력 순서를 결정적으로 만듦. 파이프라인이 아니라
    # 리다이렉트 + process-sub 라 pipefail 이 적용되지 않음. 종료코드는 "$@" 에서 rc 로 받음
    # (`|| rc=$?` 로 set -e 가 발동하지 않게). sudo 프롬프트는 어느 쪽이든 /dev/tty 로 가므로 삼켜지지 않음.
    local rc=0 teepid="" tfd=-1 hbpid=""
    if [[ "${VERBOSE:-0}" == 1 ]]; then
        exec {tfd}> >(tee -a "$log" >&2); teepid=$!
        "$@" >&"$tfd" 2>&1 || rc=$?
        exec {tfd}>&-
        wait "$teepid" 2>/dev/null || true
    else
        if [[ -t 2 && "$interactive" -eq 0 ]]; then
            # 여기서는 단계별 로그 안내를 찍지 않음 — heartbeat 가 살아있음을 보여주고, 로그 경로는
            # 실패 시(아래 step_end_fail)나 install.sh 맨 끝에서 한 번만 노출. 콘솔을 깔끔하게 유지.
            _step_heartbeat "${name}" & hbpid=$!
        fi
        "$@" >>"$log" 2>&1 || rc=$?
        if [[ -n "$hbpid" ]]; then
            kill "$hbpid" 2>/dev/null || true
            wait "$hbpid" 2>/dev/null || true
            printf '\r\033[K' >&2   # 남은 heartbeat 줄 제거
        fi
    fi

    if [[ $rc -eq 0 ]]; then
        step_end DONE
    else
        step_end FAIL
        echo "  ↳ detailed log: ${log}" >&2
        exit 1
    fi
}

#######################################
# 명령을 실행하지 않고 단계를 SKIPPED 로 기록(사용자 opt-out 등 조건부 건너뛰기).
# run_step 과 달리 실행할 명령을 받지 않음. SKIPPED 를 state 에 남겨, 이후 재개
# (step 6 reboot 후 인자 없는 재실행 포함)에서 step_should_skip 이 계속 건너뛰게 함.
# Globals:
#   STEPS_TOTAL / TOTAL_STEPS (읽기), STATE_FILE (쓰기)
# Arguments:
#   $1 - 단계 번호 n
#   $2 - 단계 이름 name
#   $3 - 건너뛴 이유 reason (콘솔 표시용, 선택)
#######################################
run_step_skip() {
    local n="$1" name="$2" reason="${3:-}"
    local total="${STEPS_TOTAL:-${TOTAL_STEPS:?run-step-skip: STEPS_TOTAL/TOTAL_STEPS not set}}"
    if [[ "${STEP_STATE}" == 1 ]] && step_should_skip "${name}"; then
        echo "[${n}/${total}] skip: ${name} (already $(_state_get "${name}" | tr '[:upper:]' '[:lower:]'))"
        return 0
    fi
    echo "[${n}/${total}] skip: ${name}${reason:+ (${reason})}"
    if [[ "${STEP_STATE}" == 1 ]]; then
        _state_set "${name}" SKIPPED
    fi
}

# ============================================================================
# 3) steps — 설치 단계 정의(install.sh 전체 시퀀스에서 호출)
# ============================================================================
# 전제: 위의 state/run_step 섹션. 호출자가 RESOURCE_DIR 를 설정.
#
# 번호 규칙: 각 stage 함수는 offset 을 받아 run_step 번호 = offset + 로컬 k 로 계산.
#   install.sh: run_stage_a01 0 → (reboot=step6, install.sh 안에 인라인) → run_stage_a03 6
#               → step 8-9(dds / network, 설치 전용, install.sh 안에 인라인).
# 애플리케이션 계층(DSR 드라이버 + RealSense + cobot2 colcon 빌드 + 컨테이너)은 더 이상 install.sh 에
# 속하지 않음 — setup-app.sh 에 있음(base 설치 이후 실행).
# offset 인자는 앞으로 부분 실행/재정렬 유연성을 위해 남겨둠 — 현재 호출자는 install.sh 뿐.
# state 키(name)는 offset/번호와 무관 — 재개 호환성에 영향 없음(같은 이름 → 같은 skip).
#
# reboot(step6)는 이 섹션에 두지 않음: install.sh 의 reboot 래퍼가 메시지 출력과 종료-vs-계속을
# 담당하고(프로세스를 종료시킴), 이는 run_step 의 일반 단계 틀과 다르기 때문.
# reboot 는 install.sh 가 인라인으로 소유.

# stage 별 단계 수(reboot 제외). 단계를 추가할 때 여기만 고치면
# install_steps_total() 의 전체 분모가 따라옴.
STAGE_A01_COUNT=5
STAGE_A03_COUNT=1
INSTALL_EXTRA_COUNT=2   # 설치 전용: dds(8) / network(9)

# install.sh 전체 분모: a01 5 + reboot 1 + a03 1 + extra 2 = 9.
install_steps_total() {
    echo $(( STAGE_A01_COUNT + 1 + STAGE_A03_COUNT + INSTALL_EXTRA_COUNT ))
}

#######################################
# a01: 커널 기준선 → NVIDIA → Docker → ROS2 desktop → ROS2 extras(reboot 은 호출자에 인라인).
# base-install.sh 는 서브커맨드마다(kernel/nvidia/docker/ros2-desktop/ros2-extras) 별도 프로세스의 별도 단계로 실행.
# Globals:
#   RESOURCE_DIR (읽기)
# Arguments:
#   $1 - 단계 번호 offset off (run_step 번호 = off + 로컬 k)
#   $2 - skip_nvidia (1 = nvidia 드라이버 단계 건너뜀, --no-nvidia-driver). 드라이버가
#        이미 별도 설치됐다고 상정 — 존재 여부 검증 안 함. 기본 0.
#######################################
run_stage_a01() {
    local off="$1" skip_nvidia="${2:-0}"
    run_step $((off + 1)) a01_kernel_baseline bash "${RESOURCE_DIR}/base-install.sh" kernel
    if [[ "$skip_nvidia" == 1 ]]; then
        run_step_skip $((off + 2)) a01_nvidia_driver "nvidia driver assumed pre-installed (--no-nvidia-driver)"
    else
        run_step $((off + 2)) a01_nvidia_driver bash "${RESOURCE_DIR}/base-install.sh" nvidia
    fi
    run_step $((off + 3)) a01_docker       bash "${RESOURCE_DIR}/base-install.sh" docker
    run_step $((off + 4)) a01_ros2_desktop bash "${RESOURCE_DIR}/base-install.sh" ros2-desktop
    run_step $((off + 5)) a01_ros2_extras  bash "${RESOURCE_DIR}/base-install.sh" ros2-extras
}

#######################################
# a03: VS Code.
# (DSR 드라이버 + RealSense + colcon 빌드는 예전 run_stage_a02 였고 setup-app.sh 로 옮김.)
# Globals:
#   RESOURCE_DIR (읽기)
# Arguments:
#   $1 - 단계 번호 offset off
#######################################
run_stage_a03() {
    local off="$1"
    run_step $((off + 1)) a03_vscode bash "${RESOURCE_DIR}/base-install.sh" vscode
}

# ============================================================================
# 4) confirm — 되돌릴 수 없는(상태 변경) 작업 전 명시적 동의
# ============================================================================
# (sudo reboot / apt purge / 드라이버 교체 같은 되돌릴 수 없는 작업은 사용자 동의 필요).
#
# 사용법:
#   confirm_or_abort "Reboot now? Unsaved work will be lost."
#
# 기본값: N. [yY] 만 진행. 비대화형 셸(TTY 없음)에서는 안전하게 중단.

confirm_or_abort() {
    local msg="$1"
    local reply=""

    # 비대화형 셸(CI / cron / systemd)에서는 기본 N — 사용자 결정 없이 절대 진행 안 함.
    if [[ ! -t 0 ]]; then
        echo "confirm: non-interactive shell, aborting." >&2
        echo "        msg: $msg" >&2
        exit 1
    fi

    read -p "${msg} (y/N): " -n 1 -r reply
    echo
    if [[ ! "$reply" =~ ^[yY]$ ]]; then
        echo "Aborted by user."
        exit 0
    fi
}

#######################################
# 같은 질문을 다시 묻고 싶지 않을 때 — 환경변수 ASSUME_YES=1 이면 자동 동의.
# CI / 자동화 래퍼가 동의를 명시적으로 표현하는 통로.
# Globals:
#   ASSUME_YES (읽기)
# Arguments:
#   $1 - 확인 메시지
#######################################
confirm_or_abort_assumable() {
    local msg="$1"
    if [[ "${ASSUME_YES:-0}" == "1" ]]; then
        echo "${msg} (auto-confirmed via ASSUME_YES=1)"
        return 0
    fi
    confirm_or_abort "$msg"
}

# ============================================================================
# 5) resume — step-6 reboot 를 넘어 설치를 자동 재개
# ============================================================================
# 일회성 GUI autostart 항목을 등록/제거 → reboot 후 install.sh 가 자동으로 이어지게 함.
#
# 동작 방식: GNOME autostart (.desktop) 가 로그인 시 터미널에서 install.sh --resume-terminal 실행.
# install.sh 가 재개로 다시 진입하면 즉시 autostart 제거(일회성)
# — 그래야 로그인할 때마다 또 실행 안 됨.

RESUME_AUTOSTART_DIR="${HOME}/.config/autostart"
RESUME_AUTOSTART_FILE="${RESUME_AUTOSTART_DIR}/ros2-jazzy-install-resume.desktop"

#######################################
# reboot 후 자동 재개 등록: 로그인 시 터미널에서 install.sh --resume-terminal 를 실행.
# 터미널 에뮬레이터가 없으면 등록을 건너뛰고 수동 재실행을 안내.
# Globals:
#   RESUME_AUTOSTART_DIR, RESUME_AUTOSTART_FILE (읽기)
# Arguments:
#   $1 - 레포 루트 경로 (repo)
#######################################
register_resume_autostart() {
    local repo="$1"
    local entry="${repo}/install.sh"
    local exec_line=""
    if command -v gnome-terminal >/dev/null; then
        exec_line="gnome-terminal -- bash \"${entry}\" --resume-terminal"
    elif command -v x-terminal-emulator >/dev/null; then
        exec_line="x-terminal-emulator -e bash \"${entry}\" --resume-terminal"
    else
        echo "[install] no terminal emulator — auto-resume not possible." >&2
        echo "             after reboot, run 'bash install.sh' manually." >&2
        return 0
    fi
    mkdir -p "${RESUME_AUTOSTART_DIR}"
    cat > "${RESUME_AUTOSTART_FILE}" <<EOF
[Desktop Entry]
Type=Application
Name=ros2_jazzy_test install resume
Comment=Auto-resume install.sh after a clean-install reboot (one-shot)
Exec=${exec_line}
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
    echo "[install] registered auto-resume after reboot: ${RESUME_AUTOSTART_FILE}" >&2
}

# autostart 항목을 제거 (멱등) — 재개 진입 시(일회성 보장)와 완료 시 호출됨.
remove_resume_autostart() {
    if [[ -f "${RESUME_AUTOSTART_FILE}" ]]; then
        rm -f "${RESUME_AUTOSTART_FILE}"
        echo "[install] removed auto-resume entry: ${RESUME_AUTOSTART_FILE}" >&2
    fi
    return 0
}

# ============================================================================
# 6) sudo-prime — sudo 비밀번호를 처음에 한 번만 받고, 이후 캐시를 살려 둠
# ============================================================================
# 사용법: sudo_prime [prefix]   # prefix 는 에러 줄의 라벨, 예: sudo_prime install / sudo_prime setup-app
#
# 왜 처음에 받나: 각 단계는 상세 출력(첫 `sudo` 프롬프트 포함)을 로그로 보내고 콘솔엔 살아있음을
# 알리는 heartbeat(작업 살아있음 신호)만 그림. 만약 비밀번호를 첫 단계 안에서 뒤늦게 받으면 그
# 프롬프트가 heartbeat 뒤에 가려져, 비밀번호를 다 입력하기도 전에 진행되는 것처럼 보임. 어떤
# 단계보다 먼저 이걸 부르면 프롬프트가 콘솔의 첫 화면이 됨 — 단계가 시작되기 전에 비밀번호를 입력.
#
# Keepalive: 60초마다 sudo 타임스탬프를 갱신해 긴 단계(드라이버 / colcon 빌드) 도중 다시 묻지 않게
# 함. 반드시 호출자(CALLER)의 셸 세션 안에 있어야 `sudo -n` 이 foreground 명령들과 같은 tty
# 타임스탬프(tty_tickets)를 갱신 — 분리된(setsid) 세션은 다른 티켓을 데워서 실제로는 살려 두지
# 못함. `( ) &` 서브셸 안의 `$$` 는 호출자 스크립트의 PID(bash) 이므로, 스크립트가 종료되면
# keepalive 도 스스로 종료됨.
sudo_prime() {
    local prefix="${1:-setup}"
    if ! sudo -v; then
        echo "${prefix}: cannot verify sudo privileges. Run as a sudo-capable regular user." >&2
        exit 1
    fi
    # 서브셸 안에서 set +e — 일시적인 sudo -n 실패나 sleep 인터럽트에 keepalive 가 조용히 죽지 않게.
    # 서브셸은 자신의 teardown 을 trap 으로 잡아 진행 중인 `sleep` 을 죽임: 안 그러면 아래 EXIT
    # trap 이 서브셸만 죽여서 `sleep` 자식이 호출자의 프로세스 그룹으로 고아가 됨 (넘겨받은 터미널
    # 에선 foreground 프로세스 그룹에 남아 입력을 막음).
    ( set +e
      trap 'kill "${_ka_sleep:-0}" 2>/dev/null; exit 0' TERM EXIT
      while kill -0 "$$" 2>/dev/null; do
          sudo -n true 2>/dev/null
          sleep 60 & _ka_sleep=$!
          wait "${_ka_sleep}"
      done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true' EXIT
}

# ============================================================================
# 7) add_apt_repo — apt 저장소·키링 등록(멱등)
# ============================================================================
# add_apt_repo: 키링 디렉터리 확보 → GPG 키 준비(없을 때만, raw/dearmor 방식) → chmod a+r →
#               apt source list 를 멱등하게(같은 명령을 여러 번 실행해도 결과가 같게) 기록 → (기본값) apt-get update.
# 호출자 = 키 파일명 / signed-by 경로를 vendor 가 쓰는 형식 그대로 전달(임의 변경 금지 — 변경 시 repo 서명 검증 깨짐).
# vendor 마다 다른 키 처리 방식(다운로더 플래그, dearmor 기록, list 비교) = 인자로 받아 그대로 유지.
#
# 사용법:
#   add_apt_repo \
#       --key-file PATH --key-url URL \
#       [--mode raw|dearmor] [--downloader curl|curl-sSf|wget] [--key-write tee|gpg-o] \
#       --list-file PATH \
#       { --list-line "deb ..." | --list-url URL --list-sed "s#..#..#g" } \
#       [--list-cmp grep|cat] [--no-update]
#
#   raw     = 키를 받은 그대로 저장(armored .asc / 원본). 항상 `sudo curl -fsSL URL -o KEY`.
#   dearmor = 바이너리 GPG 키로 변환해 저장. `<downloader> URL | gpg --dearmor | sudo tee KEY`  (--key-write tee, 기본값)
#             또는 `<downloader> URL | sudo gpg --dearmor -o KEY` (--key-write gpg-o)
#   list-cmp grep = 한 줄만 grep -qxF 로 비교(기본값) / cat = 여러 줄 전체 비교(upstream list+sed).

add_apt_repo() {
    local key_file="" key_url="" mode="raw" downloader="curl" key_write="tee"
    local list_file="" list_line="" list_url="" list_sed="" list_cmp="grep" do_update=1
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key-file)   key_file="$2";   shift 2;;
            --key-url)    key_url="$2";    shift 2;;
            --mode)       mode="$2";       shift 2;;
            --downloader) downloader="$2"; shift 2;;
            --key-write)  key_write="$2";  shift 2;;
            --list-file)  list_file="$2";  shift 2;;
            --list-line)  list_line="$2";  shift 2;;
            --list-url)   list_url="$2";   shift 2;;
            --list-sed)   list_sed="$2";   shift 2;;
            --list-cmp)   list_cmp="$2";   shift 2;;
            --no-update)  do_update=0;     shift;;
            *) echo "add_apt_repo: unknown argument '$1'" >&2; return 2;;
        esac
    done

    # 다운로더 플래그 배열(키를 stdout 으로 내보냄). vendor 마다 달라서 그대로 보존.
    local -a dl
    case "${downloader}" in
        curl)     dl=(curl -fsSL);;
        curl-sSf) dl=(curl -sSf);;
        wget)     dl=(wget -qO-);;
        *) echo "add_apt_repo: unknown downloader '${downloader}'" >&2; return 2;;
    esac

    # 1) 키링 디렉터리 + 키(없을 때만 생성 — 멱등).
    sudo install -m 0755 -d "$(dirname "${key_file}")"
    if [[ ! -f "${key_file}" ]]; then
        case "${mode}" in
            raw)
                sudo curl -fsSL "${key_url}" -o "${key_file}"
                ;;
            dearmor)
                if [[ "${key_write}" == "gpg-o" ]]; then
                    "${dl[@]}" "${key_url}" | sudo gpg --dearmor -o "${key_file}"
                else
                    "${dl[@]}" "${key_url}" | gpg --dearmor | sudo tee "${key_file}" >/dev/null
                fi
                ;;
            *) echo "add_apt_repo: unknown mode '${mode}'" >&2; return 2;;
        esac
        sudo chmod a+r "${key_file}"
    fi

    # 2) apt source list — 내용 같으면 재기록 안 함(중복 추가·덮어쓰기 방지).
    local desired
    if [[ -n "${list_url}" ]]; then
        # upstream 의 list 를 받아 signed-by 경로를 sed 로 삽입. 여러 줄이라 cat 비교가 기본값.
        desired="$("${dl[@]}" "${list_url}" | sed "${list_sed}")"
    else
        desired="${list_line}"
    fi
    local need_write=1
    if [[ -f "${list_file}" ]]; then
        if [[ "${list_cmp}" == "cat" ]]; then
            [[ "$(cat "${list_file}")" == "${desired}" ]] && need_write=0
        else
            grep -qxF "${desired}" "${list_file}" && need_write=0
        fi
    fi
    if [[ "${need_write}" == "1" ]]; then
        echo "${desired}" | sudo tee "${list_file}" >/dev/null
    fi

    # 3) apt 캐시 갱신(호출자가 --no-update 를 주면 건너뜀 — repo 추가 뒤에 별도 update 가 이어질 때).
    if [[ "${do_update}" == "1" ]]; then
        sudo apt-get update
    fi
}

# 설치 실행마다 콘솔에 찍는 저작권 배너. 재부팅 후 자동 재개된 터미널에서도 나온다.
print_copyright() {
    cat <<'EOF'
============================================================
 Cobot2 Jazzy Installer
 Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
============================================================
EOF
}
