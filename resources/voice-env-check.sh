#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/voice-env-check.sh — 음성 기능 사전 점검 (host 설치 없음).
#
# 음성/추론용 Python 패키지(langchain / openai / sounddevice 등)는 host 가 아닌
# 별도(yolo/voice) 컨테이너 안에만 설치된다. host 단계의 역할은 컨테이너가 mount 할
# .env 자격증명 점검뿐이다 (app 이미지는 공개 Drive tar → docker load 라 레지스트리 로그인 불요).
# state 호출 없음. OPENAI_API_KEY 가 없으면 그 자리에서 직접 입력받아 .env 에 기록한다
# (실패로 끊지 않음). 자격증명 값은 입력 시 화면 미표시 + 콘솔/로그에 절대 출력하지 않는다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./env-load.sh
source "${SCRIPT_DIR}/env-load.sh"
config_assert_set

REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_DIR}/.env"
ENV_EXAMPLE="${REPO_DIR}/.env.example"

# 1) .env 보장 — 없으면 템플릿에서 생성한다. 여기서 중단하지 않는다: 키는 아래 2) 에서
#    사용자가 직접 입력해 채운다 (실패로 끊는 대신 그 자리에서 입력받는 흐름).
if [[ ! -f "${ENV_FILE}" ]]; then
    if [[ -f "${ENV_EXAMPLE}" ]]; then
        cp "${ENV_EXAMPLE}" "${ENV_FILE}"
        chmod 600 "${ENV_FILE}"
        echo "voice: .env 가 없어 .env.example 로 생성했습니다 → ${ENV_FILE}" >&2
    else
        echo "voice: .env / .env.example 둘 다 없음 — 자격증명 템플릿을 먼저 준비하세요." >&2
        exit 1
    fi
fi

# 2) OPENAI_API_KEY 확보 — 이미 설정돼 있으면 통과, 비어 있으면 그 자리에서 직접 입력받아
#    .env 에 기록한다. 입력값은 화면에 표시하지 않고(read -s) 콘솔/로그에도 출력하지 않는다.
#    음성 컨테이너가 이 .env 를 runtime mount 로 사용.
# 실수로 추적 파일(.env.example)에 넣은 실제 키가 있으면 .env 로 옮기고 example 복원(secret 방지).
_relocate_example_secret "${ENV_FILE}" "${ENV_EXAMPLE}" OPENAI_API_KEY
# 키 존재 판단은 "쉘 환경변수" 가 아니라 ".env 파일 내용" 으로 한다 — 컨테이너는 .env 만 읽으므로
# (쉘 env 를 상속하지 않음), 쉘에 export 돼 있어도 .env 가 비면 컨테이너에서 키 누락으로 죽는다.
if grep -qE '^[[:space:]]*OPENAI_API_KEY=.+' "${ENV_FILE}"; then
    echo "voice: OPENAI_API_KEY 확인됨 (.env — 음성 컨테이너가 mount 로 사용)." >&2
elif [[ -t 0 ]]; then
    echo "voice: OPENAI_API_KEY 가 .env 에 없습니다. 지금 입력하면 ${ENV_FILE} 에 저장합니다." >&2
    echo "       입력값은 화면에 표시되지 않습니다. 비워 두고 Enter 하면 건너뜁니다." >&2
    printf '  OPENAI_API_KEY: ' >&2
    read -rs _openai_key
    echo >&2   # read -s 는 줄바꿈을 남기지 않으므로 수동 개행
    if [[ -n "${_openai_key}" ]]; then
        _set_env_key "${ENV_FILE}" OPENAI_API_KEY "${_openai_key}"
        unset _openai_key
        echo "voice: OPENAI_API_KEY 를 ${ENV_FILE} 에 저장했습니다 (값은 표시하지 않음)." >&2
    else
        unset _openai_key
        echo "voice: 입력이 비어 OPENAI_API_KEY 를 건너뜁니다 — 음성 컨테이너 실행 전 .env 에 설정 필요." >&2
    fi
else
    echo "voice: 경고 — OPENAI_API_KEY 가 비어 있고 비대화형 실행이라 입력받을 수 없습니다." >&2
    echo "       ${ENV_FILE} 에 'OPENAI_API_KEY=...' 를 직접 설정한 뒤 음성 컨테이너를 실행하세요." >&2
fi

echo "success checking voice environment (host 설치 없음 — 컨테이너가 실제 실행)"
