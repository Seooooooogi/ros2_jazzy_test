#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# scripts/test-state-migrate.sh — _state_migrate_legacy() 검증.
#
# 레포 이름이 ros2_jazzy_test → cobot2_jazzy_installer 로 바뀌면서 상태
# 디렉토리 경로도 바뀌었다. 기설치 머신의 상태를 옮기지 못하면 끝난 단계를
# 못 읽어 드라이버 재설치·재부팅부터 전부 다시 돈다.
#
# 가짜 HOME 에서만 돈다(실제 ~/.cobot2_jazzy_installer 무변경).
#
# Usage: bash scripts/test-state-migrate.sh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
FAKEHOME="$(mktemp -d)"
trap 'rm -rf "${FAKEHOME}"' EXIT
fails=0

# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=resources/config.sh
source "${REPO_ROOT}/resources/config.sh"
# shellcheck source=resources/lib.sh
source "${REPO_ROOT}/resources/lib.sh"

# config.sh 의 기본값이 실제 HOME 을 가리키므로 가짜 HOME 으로 다시 고정한다.
STATE_DIR="${FAKEHOME}/.cobot2_jazzy_installer"
STATE_DIR_LEGACY="${FAKEHOME}/.ros2_jazzy_test"
STATE_FILE="${STATE_DIR}/state"

check() {
    local label="$1" got="$2" want="$3"
    if [[ "${got}" == "${want}" ]]; then
        echo "  PASS ${label}"
    else
        echo "  FAIL ${label} — '${got}' (기대 '${want}')" >&2
        fails=$((fails + 1))
    fi
}

reset_fake_home() { rm -rf "${STATE_DIR}" "${STATE_DIR_LEGACY}"; }

echo "[1] 구 경로만 있으면 새 경로로 옮겨진다 — 완료 단계가 보존된다"
reset_fake_home
mkdir -p "${STATE_DIR_LEGACY}"
echo "step_nvidia=DONE" > "${STATE_DIR_LEGACY}/state"
_state_ensure_file
check "새 경로 생성됨" "$([[ -f ${STATE_FILE} ]] && echo yes || echo no)" "yes"
check "구 경로 사라짐" "$([[ -e ${STATE_DIR_LEGACY} ]] && echo yes || echo no)" "no"
check "완료 단계 보존" "$(cat "${STATE_FILE}")" "step_nvidia=DONE"
check "state 조회도 동작" "$(_state_get nvidia)" "DONE"

echo "[2] 양쪽 다 있으면 새 경로가 이긴다 — 구 경로를 덮어쓰지 않는다"
reset_fake_home
mkdir -p "${STATE_DIR_LEGACY}" "${STATE_DIR}"
echo "step_nvidia=FAILED" > "${STATE_DIR_LEGACY}/state"
echo "step_nvidia=DONE" > "${STATE_FILE}"
_state_ensure_file
check "새 경로 내용 불변" "$(cat "${STATE_FILE}")" "step_nvidia=DONE"
check "구 경로 그대로 남음" "$([[ -d ${STATE_DIR_LEGACY} ]] && echo yes || echo no)" "yes"

echo "[3] 구 경로가 없으면 아무 일도 없다 (신규 설치)"
reset_fake_home
_state_ensure_file
check "새 경로만 생성" "$([[ -f ${STATE_FILE} ]] && echo yes || echo no)" "yes"
check "구 경로 안 만듦" "$([[ -e ${STATE_DIR_LEGACY} ]] && echo yes || echo no)" "no"

echo "[4] 여러 번 호출해도 결과가 같다 (멱등)"
reset_fake_home
mkdir -p "${STATE_DIR_LEGACY}"
echo "step_docker=DONE" > "${STATE_DIR_LEGACY}/state"
_state_ensure_file
_state_ensure_file
_state_ensure_file
check "내용 불변" "$(cat "${STATE_FILE}")" "step_docker=DONE"

if [[ "${fails}" -eq 0 ]]; then
    echo "test-state-migrate: 전부 통과"
else
    echo "test-state-migrate: ${fails}건 실패" >&2
    exit 1
fi
