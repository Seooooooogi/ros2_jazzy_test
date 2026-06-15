#!/usr/bin/env bash
# shellcheck shell=bash
# resources/orchestrate.sh — install step 엔진 (상태추적 + 실행래퍼 + step 정의 단일 소스).
# source 전용 라이브러리 — set -euo 를 여기 두지 않는다(호출 진입점이 셸 옵션을 소유).
#
# 세 관심사를 한 파일로 묶는다 — 항상 함께 source 되며 step 한 단위를 따라가려면 셋 다 읽어야 한다:
#   1) state   — step 진행 상태(DONE/FAIL/SKIPPED/RUNNING)를 state 파일에 멱등 기록 (resume + [n/total]).
#   2) run_step — skip 판정 + begin/end + 로그 분리 + heartbeat 를 묶는 중앙 실행 래퍼.
#   3) steps   — install.sh 전체 시퀀스가 호출하는 step 정의(스테이지 함수 + 분모 상수).
#
# 선행 source 필요: config.sh (STATE_FILE / LOG_FILE / STATE_DIR / TOTAL_STEPS). 호출자가
# RESOURCE_DIR 와 STEPS_TOTAL 을 설정한다. 함수는 call-time resolve 라 source 순서는 무관.

# ============================================================================
# 1) state — step progress tracking (resumable 재실행 + [n/total] 진행률)
# ============================================================================
# State file format (key=value — grep/sed 기반 in-place 갱신으로 idempotent 상태 기록):
#   step_<name>=DONE|FAIL|SKIPPED|RUNNING
#
# Usage (from installer step):
#   step_should_skip a01_prerequirements && return 0
#   step_begin 1 6 a01_prerequirements
#   ... do work ...
#   step_end_ok       # 또는 실패 시 step_end_fail
#
# Idempotent: 같은 step 을 여러 번 RUNNING -> DONE 마킹해도 state 파일은 1줄 유지.
# Dependencies: config.sh 의 STATE_FILE 이 정의되어 있어야 함.

# 내부 상태: 현재 진행 중인 step name (step_begin -> step_end_* 짝짓기용)
__current_step=""

# Internal: state 파일이 없으면 생성.
_state_ensure_file() {
    mkdir -p "$(dirname "$STATE_FILE")"
    [[ -f "$STATE_FILE" ]] || : > "$STATE_FILE"
}

# Internal: state 파일의 step_<name> 라인을 status 로 set (없으면 추가, 있으면 교체).
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

# Public: 이미 DONE 으로 마킹된 step 인가? 반환 0 = skip 해도 됨.
step_should_skip() {
    local name="$1"
    _state_ensure_file
    grep -qE "^step_${name}=DONE$" "$STATE_FILE"
}

# Public: step 시작. 진행률 + 헤더 출력 + state 에 RUNNING 기록.
# Args: <n> <total> <name>
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

# Public: 현재 step 을 DONE 으로 마감.
step_end_ok() {
    if [[ -z "$__current_step" ]]; then
        echo "state: step_end_ok called without step_begin" >&2
        return 1
    fi
    _state_set "$__current_step" DONE
    echo "[OK]  step ${__current_step} = DONE"
    __current_step=""
}

# Public: 현재 step 을 FAIL 로 마감.
step_end_fail() {
    if [[ -z "$__current_step" ]]; then
        echo "state: step_end_fail called without step_begin" >&2
        return 1
    fi
    _state_set "$__current_step" FAIL
    echo "[FAIL] step ${__current_step} = FAIL" >&2
    __current_step=""
}

# Public: 현재 step 을 SKIPPED 로 마감 (조건부 skip 시).
step_end_skip() {
    if [[ -z "$__current_step" ]]; then
        return 1
    fi
    _state_set "$__current_step" SKIPPED
    echo "[SKIP] step ${__current_step} = SKIPPED"
    __current_step=""
}

# Public: 모든 step 상태 출력 (디버깅 / verification 용).
state_dump() {
    _state_ensure_file
    echo "--- state file: $STATE_FILE ---"
    cat "$STATE_FILE"
    echo "-------------------------------"
}

# ============================================================================
# 2) run_step — 중앙화된 step 실행 래퍼 (오케스트레이션 정책)
# ============================================================================
# 위 state 섹션(step_should_skip / step_begin / step_end_*) 과 config.sh (TOTAL_STEPS) 에 의존.
#
# 진행률 분모(total)는 호출자가 설정하는 STEPS_TOTAL 을 호출 시점에 읽는다.
# install.sh 가 STEPS_TOTAL(전체 step 수, install_steps_total)을 설정한다.
# 미설정 시 config.sh 의 TOTAL_STEPS 로 fallback.
#
# state 마킹/조회는 위 state 섹션이 전담하고, 본 섹션은 skip 판정 + begin/end 호출만 묶는다.
#
# 출력 정책: step 명령(`"$@"`)의 stdout 은 config.sh 의 LOG_FILE 로만, stderr 는 콘솔과
# LOG_FILE 양쪽으로 보낸다. 콘솔에는 step_begin/step_end_* 의 진행률 배너 + 경고/에러만
# 남아 단계가 명확히 보이고, apt/pip/colcon 의 대량 출력은 로그파일로 빠진다.
#
# 실패 시 step_end_fail 로 FAIL 을 기록한 뒤 exit 1 로 직접 종료한다 — 이 경로에서는
# 호출자에 설치된 ERR trap 이 발화하지 않는다(exit 는 trap 대상이 아님). 즉 실패 보고는
# step_end_fail 의 FAIL 기록이 단일 진실이고, ERR trap 은 run_step 밖의 명령 실패만 잡는다.

# step 실행 중 콘솔이 "멈춘 듯" 보이지 않도록 경과시간을 in-place(\r)로 갱신하는 heartbeat.
# stdout 이 로그로 빠지는 비-verbose + 대화형(tty) 일 때만 띄운다. verbose 모드는 step 의
# 실제 출력(colcon n/total, apt %)이 콘솔로 흐르므로 heartbeat 를 띄우지 않는다.
# 첫 draw 를 2초 뒤로 미룬다: 짧은 step / step 초반의 sudo 비밀번호 프롬프트가 heartbeat
# 라인과 겹치지 않게 — sudo 는 보통 step 시작 직후에 묻고 그 안에 끝난다.
_step_heartbeat() {
    local name="$1" start="$SECONDS" e
    while :; do
        sleep 2
        e=$(( SECONDS - start ))
        printf '\r  ⋯ %s 진행 중 (%02d:%02d 경과)\033[K' "$name" $(( e / 60 )) $(( e % 60 )) >&2
    done
}

# run_step [--interactive] <n> <name> <cmd...> — DONE 이면 skip, 아니면 begin → 실행 → ok/fail.
# --interactive: step 이 stdin 으로 사용자 입력을 받는 경우(예: API 키 직접 입력) heartbeat 를
#   끈다. heartbeat 의 \r 갱신이 입력 프롬프트를 덮어써 입력이 엉키는 것을 방지.
run_step() {
    local interactive=0
    if [[ "${1:-}" == --interactive ]]; then interactive=1; shift; fi
    local n="$1" name="$2"
    shift 2
    if [[ $# -eq 0 ]]; then
        echo "run-step: '${name}' 에 실행할 명령이 없습니다 (run_step <n> <name> <cmd...>)." >&2
        exit 2
    fi
    local total="${STEPS_TOTAL:-${TOTAL_STEPS:?run-step: STEPS_TOTAL/TOTAL_STEPS 미설정}}"
    if step_should_skip "${name}"; then
        echo "[${n}/${total}] skip: ${name} (이미 DONE)"
        return 0
    fi
    # 설치 상세 로그(config.sh 의 LOG_FILE)에 step 구분 배너 append. LOG_FILE 미정의
    # 환경(구버전 source 순서)에서도 set -u 로 죽지 않게 STATE_DIR 기준 폴백.
    local log="${LOG_FILE:-${STATE_DIR:?run-step: STATE_DIR 미설정}/install.log}"
    mkdir -p "$(dirname "$log")"
    { echo; echo "===== [${n}/${total}] ${name} — $(date '+%F %T') ====="; } >>"$log"

    step_begin "${n}" "${total}" "${name}"

    # 출력 분리: 명령 stdout 은 로그 전용, stderr 는 콘솔(>&2) + 로그(tee -a).
    # 콘솔에는 진행률 배너 + 경고/에러만 남고 apt/pip/colcon 의 대량 stdout 은 로그로 빠진다.
    #
    # tee 는 비동기 process-sub 라 명령 종료 후에도 잔여 버퍼를 flush 중일 수 있다. 그대로
    # 두면 step_end_* 의 [OK]/[FAIL] 배너가 명령의 마지막 stderr 보다 먼저 찍혀 출력이
    # 뒤섞인다. 그래서 tee 를 exec 로 전용 fd 에 1회 띄우고 PID 를 잡아, 명령 종료 후 fd 를
    # 닫아 EOF 를 주고 wait 로 drain 을 끝낸 뒤에야 배너를 찍어 순서를 결정적으로 만든다.
    #
    # 파이프라인이 아니라 리다이렉트 + process-sub 라 pipefail 과 무관하고, exit code 는
    # "$@" 의 것을 rc 에 그대로 받는다(`|| rc=$?` 라 set -e 도 미발화). sudo 프롬프트는
    # /dev/tty 로 나가므로 이 리다이렉트에 삼켜지지 않는다.
    #
    # VERBOSE=1 이면 step 의 stdout 도 tee 로 콘솔+로그 양쪽에 흘려 colcon `[n/total]`,
    # apt 퍼센트 같은 step-내 진행률을 실시간으로 보여준다. 기본(비-verbose)은 stdout 을
    # 로그 전용으로 두는 대신, 살아있음을 알리는 경과시간 heartbeat 를 콘솔에 띄운다.
    local rc=0 teepid tfd hbpid=""
    exec {tfd}> >(tee -a "$log" >&2); teepid=$!
    if [[ "${VERBOSE:-0}" == 1 ]]; then
        "$@" >&"$tfd" 2>&1 || rc=$?
    else
        if [[ -t 2 && "$interactive" -eq 0 ]]; then
            echo "  (상세 진행: tail -f ${log})" >&2
            _step_heartbeat "${name}" & hbpid=$!
        fi
        "$@" >>"$log" 2>&"$tfd" || rc=$?
        if [[ -n "$hbpid" ]]; then
            kill "$hbpid" 2>/dev/null || true
            wait "$hbpid" 2>/dev/null || true
            printf '\r\033[K' >&2   # heartbeat 잔여 라인 제거
        fi
    fi
    exec {tfd}>&-
    wait "$teepid" 2>/dev/null || true

    if [[ $rc -eq 0 ]]; then
        step_end_ok
    else
        step_end_fail
        echo "  ↳ 상세 로그: ${log}" >&2
        exit 1
    fi
}

# ============================================================================
# 3) steps — install step 정의 (install.sh 전체 시퀀스에서 호출)
# ============================================================================
# 선행: 위 state/run_step 섹션. 호출자가 RESOURCE_DIR 를 설정한다.
#
# 번호 규칙: 각 스테이지 함수는 offset 을 받아 run_step 번호 = offset + 로컬k 로 계산한다.
#   install.sh: run_stage_a01 0 → (reboot=step6, install.sh 인라인) → run_stage_a02 6
#               → run_stage_a03 10 → run_stage_a04 11 → step 13-16(install 전용, install.sh 인라인).
# offset 인자는 향후 부분 실행/재배치 여지를 위해 남겨 둔다 — 현재 호출자는 install.sh 하나.
# state key(name)는 offset/번호와 무관 — resume 호환에 영향 없음(같은 name 이면 skip 동일).
#
# reboot(step6)는 본 섹션에 두지 않는다: install.sh 의 reboot wrapper 가 메시지/UNATTENDED
# 분기/exit-vs-continue 를 소유해 run_step 의 일반 step 프레이밍과 다르기 때문이다.
# install.sh 가 reboot 를 인라인으로 소유한다(behavior-preserving 우선).

# 스테이지별 step 수 (reboot 제외). 단계 추가 시 여기 한 곳만 갱신하면
# install_steps_total() 의 전체 분모가 따라온다.
STAGE_A01_COUNT=5
STAGE_A02_COUNT=4
STAGE_A03_COUNT=1
STAGE_A04_COUNT=1
INSTALL_EXTRA_COUNT=4   # install 전용: dds(13) / toolkit(14) / container(15) / network(16)

# install.sh 전체 분모: a01 5 + reboot 1 + a02 4 + a03 1 + a04 1 + extra 4 = 16.
install_steps_total() {
    echo $(( STAGE_A01_COUNT + 1 + STAGE_A02_COUNT + STAGE_A03_COUNT \
             + STAGE_A04_COUNT + INSTALL_EXTRA_COUNT ))
}

# a01: 커널 베이스라인 → NVIDIA → Docker → ROS2 desktop → ROS2 extras (reboot 은 호출자 인라인).
# ros2-packages.sh 는 desktop/extras 두 서브커맨드를 각각 별도 step·별도 프로세스로 실행한다.
run_stage_a01() {
    local off="$1"
    run_step $((off + 1)) a01_kernel_baseline bash "${RESOURCE_DIR}/kernel-baseline.sh"
    run_step $((off + 2)) a01_nvidia_driver   bash "${RESOURCE_DIR}/nvidia-driver-install.sh"
    run_step $((off + 3)) a01_docker          bash "${RESOURCE_DIR}/docker-install.sh"
    run_step $((off + 4)) a01_ros2_desktop    bash "${RESOURCE_DIR}/ros2-packages.sh" desktop
    run_step $((off + 5)) a01_ros2_extras     bash "${RESOURCE_DIR}/ros2-packages.sh" extras
}

# a02: Doosan DSR → RealSense SDK → RealSense ROS 래퍼 → colcon 빌드.
# realsense-install.sh 는 sdk/ros 두 서브커맨드를 각각 별도 step·별도 프로세스로 실행한다.
run_stage_a02() {
    local off="$1"
    run_step $((off + 1)) a02_dsr_project    bash "${RESOURCE_DIR}/dsr-project-install.sh"
    run_step $((off + 2)) a02_realsense_sdk  bash "${RESOURCE_DIR}/realsense-install.sh" sdk
    run_step $((off + 3)) a02_realsense_ros  bash "${RESOURCE_DIR}/realsense-install.sh" ros
    run_step $((off + 4)) a02_colcon_build   bash "${RESOURCE_DIR}/colcon-build.sh"
}

# a03: VS Code.
run_stage_a03() {
    local off="$1"
    run_step $((off + 1)) a03_vscode bash "${RESOURCE_DIR}/vscode-install.sh"
}

# a04: 음성 사전 점검(.env). 사용자 입력을 받으므로 --interactive (heartbeat 억제).
run_stage_a04() {
    local off="$1"
    run_step --interactive $((off + 1)) a04_voice_env bash "${RESOURCE_DIR}/voice-env-check.sh"
}
