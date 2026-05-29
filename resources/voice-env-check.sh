#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/voice-env-check.sh — 음성 기능 사전 점검 (host 설치 없음).
#
# 음성/추론용 Python 패키지(langchain / openai / sounddevice 등)는 host 가 아닌
# 별도(yolo/voice) 컨테이너 안에만 설치된다. host 단계의 역할은 컨테이너가 mount 할
# .env 자격증명 점검 + 이미지 받기 전 Docker Hub 로그인 안내뿐이다.
# 순수 점검 본문 — state 호출 없음. 자격증명 값은 절대 출력/로그하지 않는다.
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

# 1) .env 존재 확인 — 없으면 템플릿에서 생성하고 안내 후 중단 (값 입력 필요).
if [[ ! -f "${ENV_FILE}" ]]; then
    if [[ -f "${ENV_EXAMPLE}" ]]; then
        cp "${ENV_EXAMPLE}" "${ENV_FILE}"
        echo "voice: .env 가 없어 .env.example 로 생성했습니다 → ${ENV_FILE}"
        echo "voice: OPENAI_API_KEY 등 placeholder 를 실제 값으로 채운 뒤 다시 실행하세요."
    else
        echo "voice: .env / .env.example 둘 다 없음 — 자격증명 템플릿을 먼저 준비하세요." >&2
    fi
    exit 1
fi

# 2) OPENAI_API_KEY 점검 (값은 출력 안 함). 음성 컨테이너가 .env mount 로 사용.
_load_env "${ENV_FILE}"
if _require_env OPENAI_API_KEY 2>/dev/null; then
    echo "voice: OPENAI_API_KEY 확인됨 (음성 컨테이너가 .env mount 로 사용)."
else
    echo "voice: 경고 — OPENAI_API_KEY 가 비어 있습니다. 음성 컨테이너 실행 전 .env 에 설정 필요." >&2
fi

# 3) Docker Hub 로그인 안내 — 애플리케이션 이미지 pull 전제.
#    로그인 여부의 권위 있는 소스는 ~/.docker/config.json 의 auths 항목이다
#    (docker info 출력의 Username 필드는 버전/설정에 따라 없어 신뢰 불가).
if grep -q 'index.docker.io' "${HOME}/.docker/config.json" 2>/dev/null; then
    echo "voice: Docker Hub 자격증명 설정 감지됨 (~/.docker/config.json)."
else
    echo "voice: 안내 — 애플리케이션 이미지(yolo/voice) pull 전 'docker login' 이 필요할 수 있습니다."
fi

echo "success checking voice environment (host 설치 없음 — 컨테이너가 실제 실행)"
