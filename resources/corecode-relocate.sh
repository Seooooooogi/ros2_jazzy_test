#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# resources/corecode-relocate.sh — 레포의 corecode/ 튜토리얼을 사용자 홈으로 이동(install.sh step 17).
#
# corecode/ 안 = 독립 실행 튜토리얼(Calibration_Tutorial / VoiceProcessing). 설치 완료 후 이것들을
# ${HOME}/corecode 로 이동. 이렇게 하면 인스톨러를 어디서 받아 실행했든(예: USB 같은 이동식 매체나 임시 clone)
# 상관없이 튜토리얼을 따로 사용 가능. 일반 설치 사용자 권한으로 실행 → ${HOME} 쓰기 가능 + sudo 불필요.
#
# 멱등(여러 번 실행해도 결과 동일): 목적지(DEST) 이미 존재 또는 원본(SRC) 사라짐(이미 옮김) → 아무 작업
# 안 함. 목적지 절대 덮어쓰기 금지 — 원본·목적지 둘 다 존재 시 이동 건너뜀 + 사람이 직접 확인하도록
# 경고를 로그에 기록(다시 clone 한 레포가 이미 옮겨둔·수정했을 수도 있는 사본을 덮어쓰지 않으려는 것).
# 이 스크립트 = 순수 설치 본문 — 단계 상태 관리(run_step) = 호출자(install.sh) 담당.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="${REPO_DIR}/corecode"
DEST="${HOME}/corecode"

if [[ -d "${DEST}" ]]; then
    if [[ -d "${SRC}" ]]; then
        echo "corecode: ${DEST} already exists — leaving ${SRC} in place to avoid overwrite (skip)" >&2
    else
        echo "corecode: already relocated to ${DEST} (skip)"
    fi
    exit 0
fi

if [[ ! -d "${SRC}" ]]; then
    echo "corecode: source ${SRC} not found — nothing to relocate (skip)"
    exit 0
fi

mv "${SRC}" "${DEST}"
echo "corecode: moved ${SRC} -> ${DEST}"
