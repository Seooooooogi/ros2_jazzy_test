#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# scripts/merge-to-main.sh — merge <source-branch> into main while excluding Claude-only paths.
#
# main is the branch for external (other-machine) public install verification. Claude collaboration
# artifacts (guidelines·memory·profiles) like CLAUDE.md / .claude/ are kept only on the dev branch, not on main.
# Single source of excluded paths = .claude-main-exclude at the repo root.
#
# Behavior: checkout main → --no-ff --no-commit merge (before finalizing the tree) → remove excluded paths →
#       abort if conflicts remain outside Claude paths (manual resolution) → otherwise commit.
# Excluded paths are removed again on every merge (if a previous merge deleted those paths on main, the next
# merge gets a modify/delete conflict, and this removal also resolves it).
#
# Usage: bash scripts/merge-to-main.sh <source-branch>
#   e.g.: bash scripts/merge-to-main.sh refactor/installer-shell
# The MAIN_BRANCH env var can change the target branch (default main — for test/staging).
set -euo pipefail

SRC="${1:?usage: merge-to-main.sh <source-branch>  (e.g.: refactor/installer-shell)}"
TARGET="${MAIN_BRANCH:-main}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
EXCLUDE_FILE="${REPO_ROOT}/.claude-main-exclude"

[[ -f "${EXCLUDE_FILE}" ]] || { echo "merge-to-main: ${EXCLUDE_FILE} does not exist." >&2; exit 1; }

# Abort if there are uncommitted changes to tracked files (merge is destructive). Untracked files are fine.
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "merge-to-main: there are uncommitted changes. commit/stash, then retry." >&2
    exit 1
fi

# load excluded paths (excluding blank lines/comments).
mapfile -t EXCLUDES < <(grep -vE '^[[:space:]]*(#|$)' "${EXCLUDE_FILE}")
[[ ${#EXCLUDES[@]} -gt 0 ]] || { echo "merge-to-main: the excluded-paths list is empty." >&2; exit 1; }

# Read the keep-ours list too before checkout (= current SRC/dev version). If .main-keep-ours itself
# is registered in .claude-main-exclude, after the main checkout it is not in the working tree, and the removal loop below
# deletes it — so it must be held in memory (KEEP_OURS) beforehand for keep-ours to work in the conflict-resolution step.
KEEP_OURS_FILE="${REPO_ROOT}/.main-keep-ours"
KEEP_OURS=()
if [[ -f "${KEEP_OURS_FILE}" ]]; then
    mapfile -t KEEP_OURS < <(grep -vE '^[[:space:]]*(#|$)' "${KEEP_OURS_FILE}")
fi

git checkout "${TARGET}"

# --no-ff --no-commit: creates a window to strip out Claude paths before finalizing the merge-commit tree.
# Proceed even on conflict (below, Claude paths are resolved by removal, others are checked then aborted).
git merge --no-ff --no-commit "${SRC}" || true

# If there is nothing to merge (already up to date), exit quietly.
if [[ ! -e "$(git rev-parse --git-dir)/MERGE_HEAD" ]] && git diff --cached --quiet; then
    echo "merge-to-main: nothing to merge ('${TARGET}' already includes '${SRC}')."
    exit 0
fi

# remove excluded paths from the index+working tree (this also resolves modify/delete conflicts).
for p in "${EXCLUDES[@]}"; do
    git rm -r --quiet --cached --ignore-unmatch -- "${p}" >/dev/null 2>&1 || true
    rm -rf -- "${REPO_ROOT:?}/${p}"
done

# Files where main keeps its own version (README, etc.): on conflict, do not overwrite with dev, preserve the main (ours) version.
# The list was read earlier (before checkout = SRC/dev version) into KEEP_OURS — because .main-keep-ours
# is an excluded target and may not be in the working tree at this point.
if [[ ${#KEEP_OURS[@]} -gt 0 ]]; then
    for f in "${KEEP_OURS[@]}"; do
        # resolve only those in unmerged (conflict) state to ours (main).
        if git ls-files -u -- "${f}" | grep -q .; then
            git checkout --ours -- "${f}" 2>/dev/null || true
            git add -- "${f}"
        fi
    done
fi

# If unresolved conflicts (unmerged) remain besides excluded/keep-ours, abort for a human to handle.
leftover=""
while IFS= read -r f; do
    [[ -z "${f}" ]] && continue
    skip=0
    for p in "${EXCLUDES[@]}"; do
        case "${f}" in "${p%/}" | "${p%/}"/*) skip=1; break ;; esac
    done
    [[ ${skip} -eq 0 ]] && leftover+="  ${f}"$'\n'
done < <(git ls-files -u | awk '{print $4}' | sort -u)

if [[ -n "${leftover}" ]]; then
    echo "merge-to-main: conflicts remain outside Claude paths — resolve manually then 'git commit':" >&2
    printf '%s' "${leftover}" >&2
    exit 1
fi

git commit --no-edit
echo "merge-to-main: merged '${SRC}' → '${TARGET}' (excluded: ${EXCLUDES[*]})."
echo "  verify: bash scripts/check-no-claude-on-main.sh '${TARGET}'"
