#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck shell=bash
# resources/orchestrate.sh — 설치 단계 엔진(state 추적 + 실행 래퍼 + 단계 정의를 한 파일에 통합).
# source 전용 라이브러리 — set -euo 를 여기 두지 않는다(호출 진입점이 셸 옵션을 소유).
#
# 한 파일에 세 가지 역할을 묶음 — 항상 함께 source 됨, 한 단계를 따라가려면 셋을 모두 읽어야 함:
#   1) state   — 단계 진행 상태(DONE/FAIL/SKIPPED/RUNNING)를 state 파일에 멱등하게 기록(재개 + [n/total]).
#   2) run_step — skip 판단 + begin/end + 로그 분리 + heartbeat 를 묶은 중앙 실행 래퍼.
#   3) steps   — install.sh 전체 시퀀스가 호출하는 단계 정의(stage 함수 + 분모 상수).
#
# config.sh 가 먼저 source 되어 있어야 함(STATE_FILE / LOG_FILE / STATE_DIR / TOTAL_STEPS). 호출자가
# RESOURCE_DIR 와 STEPS_TOTAL 을 설정. 함수는 호출 시점에 이름을 해석하므로 source 순서는 무관.

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
#   step_end_ok       # 실패 시엔 step_end_fail
#
# 멱등: 같은 단계를 RUNNING -> DONE 으로 여러 번 기록해도 state 파일에는 한 줄만 남음.
# 의존성: config.sh 의 STATE_FILE 가 정의돼 있어야 함.

# 내부 상태: 현재 실행 중인 단계 이름(step_begin -> step_end_* 짝 맞추기용).
__current_step=""

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
# 이 단계가 이미 DONE 으로 기록됐는지 확인.
# Globals:
#   STATE_FILE (읽기)
# Arguments:
#   $1 - 단계 이름 name
# Returns:
#   0 = 이미 DONE(건너뛰어도 안전), 1 = 아직 완료 안 됨
#######################################
step_should_skip() {
    local name="$1"
    _state_ensure_file
    grep -qE "^step_${name}=DONE$" "$STATE_FILE"
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
    _state_set "$name" RUNNING
}

#######################################
# 현재 단계를 DONE 으로 마무리.
# Globals:
#   __current_step (읽기/쓰기), STATE_FILE (쓰기)
# Outputs:
#   step_begin 없이 호출되면 stderr 에 에러 메시지
# Returns:
#   step_begin 없이 호출되면 1
#######################################
step_end_ok() {
    if [[ -z "$__current_step" ]]; then
        echo "state: step_end_ok called without step_begin" >&2
        return 1
    fi
    _state_set "$__current_step" DONE
    echo "[OK]  step ${__current_step} = DONE"
    __current_step=""
}

#######################################
# 현재 단계를 FAIL 로 마무리.
# Globals:
#   __current_step (읽기/쓰기), STATE_FILE (쓰기)
# Outputs:
#   FAIL 기록을 stderr 로 출력. step_begin 없이 호출되면 에러 메시지
# Returns:
#   step_begin 없이 호출되면 1
#######################################
step_end_fail() {
    if [[ -z "$__current_step" ]]; then
        echo "state: step_end_fail called without step_begin" >&2
        return 1
    fi
    _state_set "$__current_step" FAIL
    echo "[FAIL] step ${__current_step} = FAIL" >&2
    __current_step=""
}

#######################################
# 현재 단계를 SKIPPED 로 마무리(조건부 건너뛰기 시).
# Globals:
#   __current_step (읽기/쓰기), STATE_FILE (쓰기)
# Returns:
#   step_begin 없이 호출되면 1
#######################################
step_end_skip() {
    if [[ -z "$__current_step" ]]; then
        return 1
    fi
    _state_set "$__current_step" SKIPPED
    echo "[SKIP] step ${__current_step} = SKIPPED"
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
    if step_should_skip "${name}"; then
        echo "[${n}/${total}] skip: ${name} (already DONE)"
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
        step_end_ok
    else
        step_end_fail
        echo "  ↳ detailed log: ${log}" >&2
        exit 1
    fi
}

# ============================================================================
# 3) steps — 설치 단계 정의(install.sh 전체 시퀀스에서 호출)
# ============================================================================
# 전제: 위의 state/run_step 섹션. 호출자가 RESOURCE_DIR 를 설정.
#
# 번호 규칙: 각 stage 함수는 offset 을 받아 run_step 번호 = offset + 로컬 k 로 계산.
#   install.sh: run_stage_a01 0 → (reboot=step6, install.sh 안에 인라인) → run_stage_a03 6
#               → step 8-10(dds / network / corecode, 설치 전용, install.sh 안에 인라인).
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
INSTALL_EXTRA_COUNT=3   # 설치 전용: dds(8) / network(9) / corecode(10)

# install.sh 전체 분모: a01 5 + reboot 1 + a03 1 + extra 3 = 10.
install_steps_total() {
    echo $(( STAGE_A01_COUNT + 1 + STAGE_A03_COUNT + INSTALL_EXTRA_COUNT ))
}

#######################################
# a01: 커널 기준선 → NVIDIA → Docker → ROS2 desktop → ROS2 extras(reboot 은 호출자에 인라인).
# ros2-packages.sh 는 desktop/extras 하위 명령을 각각 별도 프로세스의 별도 단계로 실행.
# Globals:
#   RESOURCE_DIR (읽기)
# Arguments:
#   $1 - 단계 번호 offset off (run_step 번호 = off + 로컬 k)
#######################################
run_stage_a01() {
    local off="$1"
    run_step $((off + 1)) a01_kernel_baseline bash "${RESOURCE_DIR}/kernel-baseline.sh"
    run_step $((off + 2)) a01_nvidia_driver   bash "${RESOURCE_DIR}/nvidia-driver-install.sh"
    run_step $((off + 3)) a01_docker          bash "${RESOURCE_DIR}/docker-install.sh"
    run_step $((off + 4)) a01_ros2_desktop    bash "${RESOURCE_DIR}/ros2-packages.sh" desktop
    run_step $((off + 5)) a01_ros2_extras     bash "${RESOURCE_DIR}/ros2-packages.sh" extras
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
    run_step $((off + 1)) a03_vscode bash "${RESOURCE_DIR}/vscode-install.sh"
}
