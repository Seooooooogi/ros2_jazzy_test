#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# a03-vs-code-install.sh — 개발 편의 도구 (Visual Studio Code).
#
# 본 스크립트가 state 프레이밍(run_step)을 소유 — 자식 resource 스크립트는 순수 설치 본문.
# 재실행 안전: 완료 단계는 state 파일 기준 skip.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="${SCRIPT_DIR}/resources"

# root 직접 실행 금지 — HOME=/root 가 되어 state / 설치 흔적이 /root 로 잘못 들어간다.
if [[ "$(id -u)" -eq 0 ]]; then
    echo "a03: sudo 로 실행하지 마세요. 일반 사용자로 'bash a03-vs-code-install.sh' 실행." >&2
    echo "     (필요한 명령은 스크립트가 알아서 sudo 로 호출합니다.)" >&2
    exit 1
fi

# shellcheck source=resources/config.sh
source "${RESOURCE_DIR}/config.sh"
# shellcheck source=resources/state.sh
source "${RESOURCE_DIR}/state.sh"
config_assert_set

A03_STEPS=1

# run_step <n> <name> <cmd...> — DONE 이면 skip, 아니면 begin → 실행 → ok/fail 마킹.
run_step() {
    local n="$1" name="$2"
    shift 2
    if step_should_skip "${name}"; then
        echo "[${n}/${A03_STEPS}] skip: ${name} (이미 DONE)"
        return 0
    fi
    step_begin "${n}" "${A03_STEPS}" "${name}"
    if "$@"; then
        step_end_ok
    else
        step_end_fail
        exit 1
    fi
}

run_step 1 a03_vscode bash "${RESOURCE_DIR}/vscode-install.sh"

state_dump
echo "a03: 완료 — Visual Studio Code 설치"
