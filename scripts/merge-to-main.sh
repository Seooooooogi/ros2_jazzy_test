#!/usr/bin/env bash
# scripts/merge-to-main.sh — <source-branch> 를 main 에 병합하되 Claude 전용 경로는 제외한다.
#
# main 은 외부(타 머신) 공개 설치 검증용 브랜치다. CLAUDE.md / .claude/ 같은 Claude 협업
# 산출물(지침·메모리·프로파일)은 dev 브랜치에서만 유지하고 main 에는 두지 않는다.
# 제외 경로 단일 소스 = repo 루트의 .claude-main-exclude.
#
# 동작: main 체크아웃 → --no-ff --no-commit 병합(트리 확정 전) → 제외 경로 제거 →
#       Claude 경로 외 충돌이 남으면 중단(수동 해소) → 아니면 commit.
# 제외 경로는 매 병합마다 다시 제거된다(이전 머지에서 main 이 그 경로를 삭제했으면 다음
# 병합 때 modify/delete 충돌이 나는데, 그 충돌도 이 제거가 해소한다).
#
# 사용: bash scripts/merge-to-main.sh <source-branch>
#   예: bash scripts/merge-to-main.sh refactor/installer-shell
# MAIN_BRANCH 환경변수로 대상 브랜치를 바꿀 수 있다(기본 main — 테스트/스테이징용).
set -euo pipefail

SRC="${1:?usage: merge-to-main.sh <source-branch>  (예: refactor/installer-shell)}"
TARGET="${MAIN_BRANCH:-main}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
EXCLUDE_FILE="${REPO_ROOT}/.claude-main-exclude"

[[ -f "${EXCLUDE_FILE}" ]] || { echo "merge-to-main: ${EXCLUDE_FILE} 가 없습니다." >&2; exit 1; }

# 추적 파일에 미커밋 변경이 있으면 중단(병합은 destructive). 미추적 파일은 무방.
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "merge-to-main: 미커밋 변경이 있습니다. commit/stash 후 재시도하세요." >&2
    exit 1
fi

# 제외 경로 로드(빈 줄/주석 제외).
mapfile -t EXCLUDES < <(grep -vE '^[[:space:]]*(#|$)' "${EXCLUDE_FILE}")
[[ ${#EXCLUDES[@]} -gt 0 ]] || { echo "merge-to-main: 제외 경로 목록이 비어 있습니다." >&2; exit 1; }

# keep-ours 목록도 checkout 전(=현재 SRC/dev 버전)에 미리 읽어 둔다. .main-keep-ours 자체가
# .claude-main-exclude 에 등록돼 있으면 main checkout 후엔 working tree 에 없고, 아래 제거 루프가
# 지워 버린다 — 그 전에 메모리(KEEP_OURS)로 떠 둬야 충돌 해소 단계에서 keep-ours 가 동작한다.
KEEP_OURS_FILE="${REPO_ROOT}/.main-keep-ours"
KEEP_OURS=()
if [[ -f "${KEEP_OURS_FILE}" ]]; then
    mapfile -t KEEP_OURS < <(grep -vE '^[[:space:]]*(#|$)' "${KEEP_OURS_FILE}")
fi

git checkout "${TARGET}"

# --no-ff --no-commit: 머지 커밋 트리를 확정하기 전에 Claude 경로를 떼어낼 틈을 만든다.
# 충돌이 나도 일단 진행(아래에서 Claude 경로는 제거로 해소, 그 외는 검사 후 중단).
git merge --no-ff --no-commit "${SRC}" || true

# 병합할 게 없으면(이미 최신) 조용히 종료.
if [[ ! -e "$(git rev-parse --git-dir)/MERGE_HEAD" ]] && git diff --cached --quiet; then
    echo "merge-to-main: 병합할 변경이 없습니다('${TARGET}' 가 이미 '${SRC}' 를 포함)."
    exit 0
fi

# 제외 경로를 인덱스+워크트리에서 제거(modify/delete 충돌도 이로써 해소).
for p in "${EXCLUDES[@]}"; do
    git rm -r --quiet --cached --ignore-unmatch -- "${p}" >/dev/null 2>&1 || true
    rm -rf -- "${REPO_ROOT:?}/${p}"
done

# main 이 자기 버전을 유지할 파일(README 등): 충돌 시 dev 로 덮지 않고 main(ours) 버전 보존.
# 목록은 상단에서(checkout 전 = SRC/dev 버전) 미리 읽어 KEEP_OURS 에 담아 뒀다 — .main-keep-ours
# 가 제외 대상이라 이 시점엔 working tree 에 없을 수 있기 때문.
if [[ ${#KEEP_OURS[@]} -gt 0 ]]; then
    for f in "${KEEP_OURS[@]}"; do
        # unmerged(충돌) 상태인 것만 ours(main) 로 해소.
        if git ls-files -u -- "${f}" | grep -q .; then
            git checkout --ours -- "${f}" 2>/dev/null || true
            git add -- "${f}"
        fi
    done
fi

# 제외/keep-ours 외에 미해결 충돌(unmerged)이 남아 있으면 사람이 처리하도록 중단.
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
    echo "merge-to-main: Claude 경로 외 충돌이 남았습니다 — 수동 해소 후 'git commit' 하세요:" >&2
    printf '%s' "${leftover}" >&2
    exit 1
fi

git commit --no-edit
echo "merge-to-main: '${SRC}' → '${TARGET}' 병합 완료 (제외: ${EXCLUDES[*]})."
echo "  검증: bash scripts/check-no-claude-on-main.sh '${TARGET}'"
