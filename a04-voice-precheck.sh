#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# a04-voice-precheck.sh — 음성 기능 사전 점검 (host 에는 설치하지 않음).
#
# 음성/추론 Python 패키지는 host 가 아닌 별도(yolo/voice) 컨테이너 안에만 존재한다.
# 따라서 이 단계는 설치가 아니라, 컨테이너가 mount 할 .env 자격증명을 점검하고
# 애플리케이션 이미지 pull 전 Docker Hub 로그인을 안내하는 host 측 사전 점검이다.
# 본 스크립트가 state 프레이밍(run_step)을 소유 — 자식 resource 스크립트는 순수 점검 본문.
# 재실행 안전: 완료 단계는 state 파일 기준 skip.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="${SCRIPT_DIR}/resources"

# root 직접 실행 금지 — HOME=/root 가 되어 state / .env 경로가 /root 로 잘못 잡힌다.
if [[ "$(id -u)" -eq 0 ]]; then
    echo "a04: sudo 로 실행하지 마세요. 일반 사용자로 'bash a04-voice-precheck.sh' 실행." >&2
    exit 1
fi

# shellcheck source=resources/config.sh
source "${RESOURCE_DIR}/config.sh"
# shellcheck source=resources/state.sh
source "${RESOURCE_DIR}/state.sh"
config_assert_set

# 단독 실행 시 스테이지-로컬 진행률 ([n/1]). 통합 실행(install.sh)은 자체 STEPS_TOTAL=12 사용.
STEPS_TOTAL=1
# shellcheck source=resources/run-step.sh
source "${RESOURCE_DIR}/run-step.sh"

run_step --interactive 1 a04_voice_env bash "${RESOURCE_DIR}/voice-env-check.sh"

state_dump
echo "a04: 완료 — 음성 환경 점검 (실제 실행은 음성 컨테이너)"
