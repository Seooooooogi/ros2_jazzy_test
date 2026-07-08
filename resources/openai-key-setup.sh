#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/openai-key-setup.sh — OPENAI_API_KEY 를 .env 에 넣는 단계(setup-app.sh 가 컨테이너 셋업 중에 실행; host 에는 아무것도 설치하지 않음).
#
# voice/추론용 Python 패키지 = 앱 컨테이너 안에만 존재. 컨테이너는 실행 시 mount 로 레포 루트의
# .env 에서 OPENAI_API_KEY 를 읽음. 이 단계가 하는 일 = 딱 하나 — 그 키를 .env 에 넣기.
# 절대 도중에 멈추지(fail-stop) 않음: 키 없으면 한 번만 물어봄(입력 숨김), 빈 답도 무방 —
# 나중에 .env 직접 수정 가능. 키 값 = 입력 시 화면에 미표시 + 콘솔/로그에도 절대 미출력.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# .env 관련 헬퍼(_load_env/_require_env/_set_env_key/_relocate_example_secret) = interaction.sh 에 위치.
# shellcheck source=./interaction.sh
source "${SCRIPT_DIR}/interaction.sh"
config_assert_set

REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_DIR}/.env"
ENV_EXAMPLE="${REPO_DIR}/.env.example"

# 1) .env 준비 — 없으면 템플릿(.env.example)에서 복사해 생성. 여기서 멈추지 않음: 키는 아래 2) 에서 채움.
if [[ ! -f "${ENV_FILE}" ]]; then
    if [[ -f "${ENV_EXAMPLE}" ]]; then
        cp "${ENV_EXAMPLE}" "${ENV_FILE}"
        chmod 600 "${ENV_FILE}"
        echo "openai-key: .env was missing, created it from .env.example → ${ENV_FILE}" >&2
    else
        echo "openai-key: neither .env nor .env.example exists — prepare a credential template first." >&2
        exit 1
    fi
fi

# 2) OPENAI_API_KEY 확보 — 이미 있으면 그냥 통과; 비어 있으면 즉석에서 물어보고 .env 에 기록.
#    입력은 화면에 미표시(read -s) + 콘솔/로그에도 미출력. 앱 컨테이너는 실행 시
#    mount 로 이 .env 를 읽음.
# 추적되는 파일(.env.example)에 실제 키가 실수로 들어간 경우 → 그 값을 .env 로 옮기고 example 은 원래대로 복원(비밀값 유출 방지).
_relocate_example_secret "${ENV_FILE}" "${ENV_EXAMPLE}" OPENAI_API_KEY
# 키 존재 여부 = "셸 환경변수"가 아니라 ".env 파일 내용"으로 판단 — 컨테이너는 .env 만 읽고
# (셸 환경변수는 물려받지 않음), 그래서 셸에서 export 했더라도 .env 가 비어 있으면 컨테이너는 키 없음으로 죽음.
if grep -qE '^[[:space:]]*OPENAI_API_KEY=.+' "${ENV_FILE}"; then
    echo "openai-key: OPENAI_API_KEY confirmed (.env — the application container uses it via mount)." >&2
elif [[ -t 0 ]]; then
    echo "openai-key: OPENAI_API_KEY is not in .env. If you type it now, it will be saved to ${ENV_FILE}." >&2
    echo "           The input is not shown on screen. Leave it blank and press Enter to skip (you can edit .env later)." >&2
    printf '  OPENAI_API_KEY: ' >&2
    read -rs _openai_key
    echo >&2   # read -s 는 줄바꿈 안 남김 → 수동으로 하나 삽입
    if [[ -n "${_openai_key}" ]]; then
        _set_env_key "${ENV_FILE}" OPENAI_API_KEY "${_openai_key}"
        unset _openai_key
        echo "openai-key: saved OPENAI_API_KEY to ${ENV_FILE} (value not shown)." >&2
    else
        unset _openai_key
        echo "openai-key: input empty, skipping — set 'OPENAI_API_KEY=...' in ${ENV_FILE} before running the application container." >&2
    fi
else
    echo "openai-key: warning — OPENAI_API_KEY is empty and this is a non-interactive run, so it cannot be prompted." >&2
    echo "           Set 'OPENAI_API_KEY=...' in ${ENV_FILE} directly before running the application container." >&2
fi

echo "openai-key: done (key lives in ${ENV_FILE}; the application container reads it via mount)."
