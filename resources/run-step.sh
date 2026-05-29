#!/usr/bin/env bash
# shellcheck shell=bash
# resources/run-step.sh — 중앙화된 step 실행 래퍼 (오케스트레이션 정책).
#
# state.sh (step_should_skip / step_begin / step_end_*) 와 config.sh (TOTAL_STEPS) 가
# 먼저 source 되어 있어야 한다. 직접 실행하지 않는다.
#
# 진행률 분모(total)는 호출자가 설정하는 STEPS_TOTAL 을 호출 시점에 읽는다.
# install.sh 는 STEPS_TOTAL=11 (전체 통합), 각 a0N 오케스트레이터는 스테이지-로컬 값
# (a01=5 / a02=4 / a03=1 / a04=1) 을 설정한다. 미설정 시 config.sh 의 TOTAL_STEPS 로 fallback.
#
# state 마킹/조회는 state.sh 가 전담하고, 본 파일은 skip 판정 + begin/end 호출만 묶는다.
#
# 실패 시 step_end_fail 로 FAIL 을 기록한 뒤 exit 1 로 직접 종료한다 — 이 경로에서는
# 호출자에 설치된 ERR trap 이 발화하지 않는다(exit 는 trap 대상이 아님). 즉 실패 보고는
# step_end_fail 의 FAIL 기록이 단일 진실이고, ERR trap 은 run_step 밖의 명령 실패만 잡는다.

# run_step <n> <name> <cmd...> — DONE 이면 skip, 아니면 begin → 실행 → ok/fail 마킹.
run_step() {
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
    step_begin "${n}" "${total}" "${name}"
    if "$@"; then
        step_end_ok
    else
        step_end_fail
        exit 1
    fi
}
