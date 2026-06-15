#!/usr/bin/env bash
# =============================================================
#  ros2_jazzy_test — ROS2 Jazzy workstation installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# Phase 4 container build gate — independent of the host install (only the Docker engine is required).
#
# Builds the two application images (yolo / voice) and performs "isolated verification":
#   (1) image build success  (2) secret hygiene (docker history)  (3) in-container import smoke.
# This stage does not require GPU / microphone / camera / model weights (module import only).
# torch.cuda.is_available() / service round-trip / od_msg hash consistency are post-host-e2e stages — not verified here.
#
# The last stage of the dev-branch install.sh calls this script to include build+verification in the install
# sequence. main (install-only) does not call it, and it can also be run standalone on any branch (below).
# Usage: bash containers/build-all.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=resources/config.sh
source "${REPO_ROOT}/resources/config.sh"

# Image coordinates — DOCKERHUB_USER / *_TAG override from .env or the environment. If unset, local dev tags.
: "${DOCKERHUB_USER:=local}"
: "${YOLO_TAG:=dev}"
: "${VOICE_TAG:=dev}"
YOLO_IMAGE="docker.io/${DOCKERHUB_USER}/ros2-jazzy-yolo:${YOLO_TAG}"
VOICE_IMAGE="docker.io/${DOCKERHUB_USER}/ros2-jazzy-voice:${VOICE_TAG}"

# Explicitly print the image coordinates actually used (avoid silent defaults — run-manifest tracking).
printf 'INFO: build targets — YOLO=%s  VOICE=%s\n' "${YOLO_IMAGE}" "${VOICE_IMAGE}"
if [[ "${DOCKERHUB_USER}" == "local" ]]; then
    printf 'INFO: DOCKERHUB_USER unset → using local dev tags (cannot publish, set coordinates via .env).\n'
fi

TOTAL=5
step() { printf '\n[%d/%d] %s\n' "$1" "${TOTAL}" "$2"; }

# secret hygiene — zero credential traces in the image layer history (required). Once baked in, registry exposure is irreversible.
secret_scan() {
    local image="$1"
    if docker history --no-trunc "${image}" | grep -iE 'OPENAI|API_KEY|TOKEN|SECRET|PASSWORD'; then
        echo "  ✗ secret trace found — ${image}" >&2
        return 1
    fi
    echo "  ✓ no secret trace — ${image}"
}

# isolated import smoke — the default ENTRYPOINT (/entrypoint.sh) sources ROS2 + overlay setup.bash.
smoke() {
    local image="$1" pyexpr="$2"
    docker run --rm "${image}" python3 -c "${pyexpr}"
}

step 1 "build yolo-detection (torch cu${CUDA_VERSION//./} + ultralytics + numpy<2)"
docker build --pull \
    -f "${REPO_ROOT}/containers/yolo-detection/Dockerfile" \
    --build-arg ROS_DISTRO="${ROS_DISTRO}" \
    --build-arg CUDA_VERSION="${CUDA_VERSION}" \
    -t "${YOLO_IMAGE}" \
    "${REPO_ROOT}"

step 2 "build voice-processing (langchain + openwakeword + numpy<2)"
docker build --pull \
    -f "${REPO_ROOT}/containers/voice-processing/Dockerfile" \
    --build-arg ROS_DISTRO="${ROS_DISTRO}" \
    -t "${VOICE_IMAGE}" \
    "${REPO_ROOT}"

step 3 "secret hygiene scan (docker history)"
secret_scan "${YOLO_IMAGE}"
secret_scan "${VOICE_IMAGE}"

step 4 "isolated import smoke — yolo (no GPU/model needed)"
smoke "${YOLO_IMAGE}" \
"import torch, torchvision, ultralytics, cv2, numpy
from od_msg.srv import SrvDepthPosition
import object_detection.yolo, object_detection.realsense, object_detection.detection
assert numpy.__version__.startswith('1.'), numpy.__version__
print('  yolo import OK — numpy', numpy.__version__)"

step 5 "isolated smoke — voice (import + actual .tflite wakeword model load, no microphone/network needed)"
# import alone is not enough: the Model(.tflite) load in wakeup_word.py happens only at runtime, so even passing the import smoke,
# it fails on the real robot if the tflite backend (ai-edge-litert) is absent. Confirm here with one Model instantiation + predict.
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

printf '\n✅ build gate PASS — both images built + secret hygiene + import smoke passed.\n'
printf '   GPU runtime / service round-trip / od_msg hash consistency are verified after host e2e (out of scope for this stage).\n'
