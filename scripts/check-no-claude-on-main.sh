#!/usr/bin/env bash
# scripts/check-no-claude-on-main.sh — 주어진 ref(기본 HEAD)의 트리에 Claude 전용 경로가
# 없는지 검증한다. 있으면 비-0 종료. main 머지 후 점검 / CI 가드 / git hook 에서 사용한다.
# 제외 경로 단일 소스 = repo 루트의 .claude-main-exclude.
#
# 사용: bash scripts/check-no-claude-on-main.sh [ref]
#   예: bash scripts/check-no-claude-on-main.sh main
#       bash scripts/check-no-claude-on-main.sh origin/main
set -euo pipefail

REF="${1:-HEAD}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
EXCLUDE_FILE="${REPO_ROOT}/.claude-main-exclude"
[[ -f "${EXCLUDE_FILE}" ]] || { echo "check-no-claude-on-main: ${EXCLUDE_FILE} 가 없습니다." >&2; exit 1; }

mapfile -t EXCLUDES < <(grep -vE '^[[:space:]]*(#|$)' "${EXCLUDE_FILE}")
[[ ${#EXCLUDES[@]} -gt 0 ]] || { echo "check-no-claude-on-main: 제외 경로 목록이 비어 있습니다." >&2; exit 1; }

bad=""
while IFS= read -r f; do
    [[ -z "${f}" ]] && continue
    for p in "${EXCLUDES[@]}"; do
        case "${f}" in "${p%/}" | "${p%/}"/*) bad+="  ${f}"$'\n'; break ;; esac
    done
done < <(git ls-tree -r --name-only "${REF}")

if [[ -n "${bad}" ]]; then
    echo "check-no-claude-on-main: '${REF}' 에 Claude 전용 경로가 있습니다 (main 엔 없어야 함):" >&2
    printf '%s' "${bad}" >&2
    exit 1
fi
echo "check-no-claude-on-main: '${REF}' 깨끗 — Claude 전용 경로 없음."
