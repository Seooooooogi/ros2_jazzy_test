#!/usr/bin/env bash
# =============================================================
#  ros2_jazzy_test — ROS2 Jazzy workstation installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# scripts/check-no-claude-on-main.sh — verify the tree of the given ref (default HEAD) has no Claude-only paths.
# Exits non-zero if any exist. Used for post-main-merge checks / CI guard / git hook.
# Single source of excluded paths = .claude-main-exclude at the repo root.
#
# Usage: bash scripts/check-no-claude-on-main.sh [ref]
#   e.g.: bash scripts/check-no-claude-on-main.sh main
#         bash scripts/check-no-claude-on-main.sh origin/main
set -euo pipefail

REF="${1:-HEAD}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
EXCLUDE_FILE="${REPO_ROOT}/.claude-main-exclude"
[[ -f "${EXCLUDE_FILE}" ]] || { echo "check-no-claude-on-main: ${EXCLUDE_FILE} does not exist." >&2; exit 1; }

mapfile -t EXCLUDES < <(grep -vE '^[[:space:]]*(#|$)' "${EXCLUDE_FILE}")
[[ ${#EXCLUDES[@]} -gt 0 ]] || { echo "check-no-claude-on-main: the excluded-paths list is empty." >&2; exit 1; }

bad=""
while IFS= read -r f; do
    [[ -z "${f}" ]] && continue
    for p in "${EXCLUDES[@]}"; do
        case "${f}" in "${p%/}" | "${p%/}"/*) bad+="  ${f}"$'\n'; break ;; esac
    done
done < <(git ls-tree -r --name-only "${REF}")

if [[ -n "${bad}" ]]; then
    echo "check-no-claude-on-main: '${REF}' has Claude-only paths (must be absent on main):" >&2
    printf '%s' "${bad}" >&2
    exit 1
fi
echo "check-no-claude-on-main: '${REF}' clean — no Claude-only paths."
