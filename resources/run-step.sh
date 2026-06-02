#!/usr/bin/env bash
# shellcheck shell=bash
# resources/run-step.sh — 중앙화된 step 실행 래퍼 (오케스트레이션 정책).
#
# state.sh (step_should_skip / step_begin / step_end_*) 와 config.sh (TOTAL_STEPS) 가
# 먼저 source 되어 있어야 한다. 직접 실행하지 않는다.
#
# 진행률 분모(total)는 호출자가 설정하는 STEPS_TOTAL 을 호출 시점에 읽는다.
# install.sh 는 STEPS_TOTAL=12 (전체 통합), 각 a0N 오케스트레이터는 스테이지-로컬 값
# (a01=6 / a02=4 / a03=1 / a04=1) 을 설정한다. 미설정 시 config.sh 의 TOTAL_STEPS 로 fallback.
#
# state 마킹/조회는 state.sh 가 전담하고, 본 파일은 skip 판정 + begin/end 호출만 묶는다.
#
# 출력 정책: step 명령(`"$@"`)의 stdout 은 config.sh 의 LOG_FILE 로만, stderr 는 콘솔과
# LOG_FILE 양쪽으로 보낸다. 콘솔에는 step_begin/step_end_* 의 진행률 배너 + 경고/에러만
# 남아 단계가 명확히 보이고, apt/pip/colcon 의 대량 출력은 로그파일로 빠진다.
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
    local rc=0 teepid tfd
    exec {tfd}> >(tee -a "$log" >&2); teepid=$!
    "$@" >>"$log" 2>&"$tfd" || rc=$?
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
