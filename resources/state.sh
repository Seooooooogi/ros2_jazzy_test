#!/usr/bin/env bash
# resources/state.sh — Step progress tracking (resumable 재실행 + [n/total] 진행률).
#
# State file format (ADR 2026-05-27 구조화 선택):
#   step_<name>=DONE|FAIL|SKIPPED|RUNNING
#
# Usage (from installer step):
#   source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
#   source "$(dirname "${BASH_SOURCE[0]}")/state.sh"
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
