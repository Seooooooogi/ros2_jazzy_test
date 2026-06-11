#!/usr/bin/env bash
# shellcheck shell=bash
# resources/run-step.sh — 중앙화된 step 실행 래퍼 (오케스트레이션 정책).
# source 전용 라이브러리 — set -euo 를 여기 두지 않는다(호출 진입점이 셸 옵션을 소유).
#
# state.sh (step_should_skip / step_begin / step_end_*) 와 config.sh (TOTAL_STEPS) 가
# 먼저 source 되어 있어야 한다. 직접 실행하지 않는다.
#
# 진행률 분모(total)는 호출자가 설정하는 STEPS_TOTAL 을 호출 시점에 읽는다.
# install.sh 는 STEPS_TOTAL(전체 step 수)을, 각 a0N 오케스트레이터는 스테이지-로컬 값(a01=6 /
# a02=4 / a03=1 / a04=1)을 설정한다. 미설정 시 config.sh 의 TOTAL_STEPS 로 fallback.
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
