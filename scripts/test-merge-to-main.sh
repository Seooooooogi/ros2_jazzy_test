#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# scripts/test-merge-to-main.sh — merge-to-main.sh 의 keep-ours 동작 검증.
#
# 합성 레포를 매번 새로 만들어 dev→main 머지를 실제로 돌린다(실 레포 무변경).
# 검증 대상: .main-keep-ours 에 등록된 파일은 충돌 여부와 무관하게 main 버전이 유지되고,
# 그 외 dev 변경은 정상 전파되며, .claude-main-exclude 경로는 main 트리에서 빠진다.
#
# Usage: bash scripts/test-merge-to-main.sh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MERGE_SCRIPT="${SCRIPT_DIR}/merge-to-main.sh"
ROOT="$(mktemp -d)"
trap 'rm -rf "${ROOT}"' EXIT
fails=0

#######################################
# 시나리오용 합성 레포 생성(main + dev 브랜치).
# Arguments:
#   $1 - dev 가 README 를 고치는가 (yes/no)
#   $2 - main 이 README 를 고치는가 (yes/no)
# Outputs:
#   stdout 에 만들어진 레포 경로
#######################################
setup() {
    local dev_edits="$1" main_edits="$2" repo="${ROOT}/r${RANDOM}"
    mkdir -p "${repo}"; cd "${repo}"
    git init -q -b main
    git config user.email test@example.com; git config user.name test

    printf 'docs/\n' > .claude-main-exclude
    printf 'README.md\n' > .main-keep-ours
    printf 'MAIN v1\n' > README.md
    mkdir -p docs && printf 'internal\n' > docs/notes.md
    git add -A && git commit -qm init

    git checkout -q -b dev
    printf 'echo hi\n' > src.sh              # main 으로 전파돼야 할 실제 변경
    printf 'dev-only\n' > docs/design.md     # main 트리에서 빠져야 할 내부 문서
    [[ "${dev_edits}" == yes ]] && printf 'DEV v2\n' > README.md
    git add -A && git commit -qm dev-work

    git checkout -q main
    if [[ "${main_edits}" == yes ]]; then
        printf 'MAIN v3\n' > README.md       # GitHub 웹에서 main 을 직접 고치는 상황
        git add -A && git commit -qm web-edit
    fi
    echo "${repo}"
}

#######################################
# 한 시나리오 실행 후 결과 검사(README 내용 + 전파 + 제외).
# Arguments:
#   $1 - 시나리오 이름, $2 - dev README 수정 여부, $3 - main README 수정 여부, $4 - 기대 README 내용
# Globals:
#   fails (실패 시 1 증가)
#######################################
run() {
    local name="$1" dev_edits="$2" main_edits="$3" want="$4" repo ok=1 got
    repo="$(setup "${dev_edits}" "${main_edits}")"
    cd "${repo}"

    if ! MAIN_BRANCH=main bash "${MERGE_SCRIPT}" dev >/dev/null 2>&1; then
        echo "  ✗ ${name} — merge-to-main.sh 가 실패(abort)함"; fails=$(( fails + 1 )); return
    fi

    got="$(cat README.md)"
    [[ "${got}" == "${want}" ]] || { echo "  ✗ README='${got}' (기대 '${want}')"; ok=0; }
    [[ -f src.sh ]] || { echo "  ✗ dev 의 src.sh 가 main 에 전파되지 않음"; ok=0; }
    git ls-tree -r main --name-only | grep -q '^docs/' && { echo "  ✗ docs/ 가 main 트리에 남음"; ok=0; }

    if [[ ${ok} -eq 1 ]]; then echo "  ✓ ${name}"; else fails=$(( fails + 1 )); fi
}

#######################################
# 제외 경로 아래의 미추적 / gitignore 파일이 승격 후에도 살아남는지, 그리고 두 번째 승격에서
# 생기는 modify/delete 충돌이 자동 해소되는지 확인.
# Globals:
#   fails (실패 시 1 증가)
#######################################
run_survival() {
    local repo ok=1
    repo="$(setup no no)"
    cd "${repo}"

    printf 'ignored/\n' > .gitignore
    git add .gitignore && git commit -qm gitignore

    printf 'scratch\n' > docs/scratch.md                       # 미추적
    mkdir -p docs/ignored && printf 'blob\n' > docs/ignored/keep.bin   # gitignore 대상

    MAIN_BRANCH=main bash "${MERGE_SCRIPT}" dev >/dev/null 2>&1 \
        || { echo "  ✗ 1차 승격 실패"; fails=$(( fails + 1 )); return; }

    # dev 가 제외 경로의 추적 파일을 고친 뒤 다시 승격 → main 엔 그 파일이 없어 modify/delete 충돌.
    git checkout -q dev
    printf 'more\n' >> docs/notes.md
    git commit -qam dev-doc-edit
    MAIN_BRANCH=main bash "${MERGE_SCRIPT}" dev >/dev/null 2>&1 \
        || { echo "  ✗ 2차 승격이 modify/delete 충돌로 중단됨"; fails=$(( fails + 1 )); return; }

    [[ -f docs/scratch.md ]]      || { echo "  ✗ 미추적 파일이 삭제됨 (docs/scratch.md)"; ok=0; }
    [[ -f docs/ignored/keep.bin ]] || { echo "  ✗ gitignore 파일이 삭제됨 (docs/ignored/keep.bin)"; ok=0; }
    git ls-tree -r main --name-only | grep -q '^docs/' && { echo "  ✗ docs/ 가 main 트리에 남음"; ok=0; }
    [[ -f src.sh ]] || { echo "  ✗ dev 의 src.sh 가 전파되지 않음"; ok=0; }

    if [[ ${ok} -eq 1 ]]; then
        echo "  ✓ 재승격 후에도 미추적·gitignore 파일 생존, main 트리는 깨끗"
    else
        fails=$(( fails + 1 ))
    fi
}

echo "keep-ours = README.md → 항상 main 버전 유지, dev 의 다른 변경은 전파"
run "dev 만 README 수정 → main v1 유지"    yes no  'MAIN v1'
run "둘 다 README 수정 → main v3 유지"     yes yes 'MAIN v3'
run "main 만 README 수정 → main v3 유지"   no  yes 'MAIN v3'
run "아무도 README 미수정 → main v1 유지"  no  no  'MAIN v1'

echo
echo "제외 경로의 미추적·gitignore 파일은 승격이 지우지 않는다"
run_survival

echo
if [[ ${fails} -eq 0 ]]; then
    echo "test-merge-to-main: PASS (5/5)"
else
    echo "test-merge-to-main: FAIL (${fails}건)" >&2
    exit 1
fi
