#!/usr/bin/env bash
# Phase 4 컨테이너 빌드 게이트 — host 설치와 독립 (Docker 엔진만 필요).
#
# 두 application 이미지(yolo / voice)를 빌드하고 "개별(isolated) 검증"을 수행한다:
#   (1) 이미지 빌드 성공  (2) secret 위생(docker history)  (3) 컨테이너 내부 import smoke.
# 이 단계는 GPU / 마이크 / 카메라 / 모델 가중치를 요구하지 않는다 (모듈 import 만).
# torch.cuda.is_available() / service 왕복 / od_msg hash 정합은 host e2e 이후 단계 — 여기서 검증 안 함.
#
# install.sh 는 본 스크립트를 자동 호출하지 않는다 (host / application 책임 분리, ADR-007).
# 사용: bash containers/build-all.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=resources/config.sh
source "${REPO_ROOT}/resources/config.sh"

# 이미지 좌표 — DOCKERHUB_USER / *_TAG 는 .env 또는 환경에서 override. 미설정 시 로컬 dev 태그.
: "${DOCKERHUB_USER:=local}"
: "${YOLO_TAG:=dev}"
: "${VOICE_TAG:=dev}"
YOLO_IMAGE="docker.io/${DOCKERHUB_USER}/ros2-jazzy-yolo:${YOLO_TAG}"
VOICE_IMAGE="docker.io/${DOCKERHUB_USER}/ros2-jazzy-voice:${VOICE_TAG}"

# 실제 사용된 이미지 좌표를 명시 출력 (silent default 방지 — run manifest 추적).
printf 'INFO: 빌드 대상 — YOLO=%s  VOICE=%s\n' "${YOLO_IMAGE}" "${VOICE_IMAGE}"
if [[ "${DOCKERHUB_USER}" == "local" ]]; then
    printf 'INFO: DOCKERHUB_USER 미설정 → 로컬 dev 태그 사용 (publish 불가, .env 로 좌표 지정).\n'
fi

TOTAL=5
step() { printf '\n[%d/%d] %s\n' "$1" "${TOTAL}" "$2"; }

# secret 위생 — 이미지 레이어 history 에 자격증명 흔적 0 (ADR-007 mandatory).
secret_scan() {
    local image="$1"
    if docker history --no-trunc "${image}" | grep -iE 'OPENAI|API_KEY|TOKEN|SECRET|PASSWORD'; then
        echo "  ✗ secret 흔적 발견 — ${image}" >&2
        return 1
    fi
    echo "  ✓ secret 흔적 없음 — ${image}"
}

# isolated import smoke — 기본 ENTRYPOINT(/entrypoint.sh)가 ROS2 + overlay setup.bash 를 source.
smoke() {
    local image="$1" pyexpr="$2"
    docker run --rm "${image}" python3 -c "${pyexpr}"
}

step 1 "yolo-detection 빌드 (torch cu${CUDA_VERSION//./} + ultralytics + numpy<2)"
docker build --pull \
    -f "${REPO_ROOT}/containers/yolo-detection/Dockerfile" \
    --build-arg ROS_DISTRO="${ROS_DISTRO}" \
    --build-arg CUDA_VERSION="${CUDA_VERSION}" \
    -t "${YOLO_IMAGE}" \
    "${REPO_ROOT}"

step 2 "voice-processing 빌드 (langchain + openwakeword + numpy<2)"
docker build --pull \
    -f "${REPO_ROOT}/containers/voice-processing/Dockerfile" \
    --build-arg ROS_DISTRO="${ROS_DISTRO}" \
    -t "${VOICE_IMAGE}" \
    "${REPO_ROOT}"

step 3 "secret 위생 스캔 (docker history)"
secret_scan "${YOLO_IMAGE}"
secret_scan "${VOICE_IMAGE}"

step 4 "isolated import smoke — yolo (GPU/모델 불요)"
smoke "${YOLO_IMAGE}" \
"import torch, torchvision, ultralytics, cv2, numpy
from od_msg.srv import SrvDepthPosition
import object_detection.yolo, object_detection.realsense, object_detection.detection
assert numpy.__version__.startswith('1.'), numpy.__version__
print('  yolo import OK — numpy', numpy.__version__)"

step 5 "isolated smoke — voice (import + .tflite wakeword 모델 실제 로드, 마이크/네트워크 불요)"
# import 만으론 부족: wakeup_word.py 의 Model(.tflite) 로드는 런타임에만 일어나 import smoke 를 통과해도
# tflite 백엔드(ai-edge-litert) 부재 시 실로봇에서 실패한다. 여기서 Model 인스턴스화 + predict 1회로 확증.
smoke "${VOICE_IMAGE}" \
"import os, numpy as np
import langchain, langchain_openai, openai, pyaudio, sounddevice, scipy, openwakeword, ai_edge_litert, dotenv, numpy
import voice_processing.get_keyword, voice_processing.MicController, voice_processing.stt, voice_processing.wakeup_word
assert numpy.__version__.startswith('1.'), numpy.__version__
from ament_index_python.packages import get_package_share_directory
from openwakeword.model import Model
mp = os.path.join(get_package_share_directory('voice_processing'), 'resource', 'hello_rokey_8332_32.tflite')
m = Model(wakeword_models=[mp])
out = m.predict(np.zeros(1280, dtype=np.int16))
print('  voice OK — numpy', numpy.__version__, '| Model(.tflite) load + predict keys:', list(out.keys()))"

printf '\n✅ 빌드 게이트 PASS — 두 이미지 빌드 + secret 위생 + import smoke 통과.\n'
printf '   GPU 런타임 / service 왕복 / od_msg hash 정합은 host e2e 이후 검증 (이 단계 범위 아님).\n'
