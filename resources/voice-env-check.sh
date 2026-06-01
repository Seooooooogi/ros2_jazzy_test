#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/voice-env-check.sh — 음성 환경 점검 (application-shell variant).
#
# 본 브랜치는 host 단독 실행이라 음성/추론 Python(openwakeword / langchain / openai /
# sounddevice 등)이 host venv 에 설치돼 있다(host-python-deps.sh, openwakeword Model 로드까지
# 검증 완료). 따라서 이 단계의 역할은 host 음성 노드가 환경변수로 읽을 .env 자격증명 점검이다.
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
    echo "voice: OPENAI_API_KEY 확인됨 (host 음성 노드가 환경변수로 사용)."
else
    echo "voice: 경고 — OPENAI_API_KEY 가 비어 있습니다. 음성 노드 실행 전 .env 에 설정 필요." >&2
fi

# 3) application-shell 은 음성을 host venv 로 직접 실행한다 — 애플리케이션 이미지 pull/로그인 불요.
#    음성 패키지/모델은 a02(host-python-deps + colcon-build)에서 설치·검증 완료.
echo "voice: host venv 로 직접 실행 — 'source resources/activate.sh' 후 'ros2 run voice_processing get_keyword'."

echo "success checking voice environment (host venv 가 직접 실행)"
