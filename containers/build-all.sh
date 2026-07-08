#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# containers/build-all.sh — 앱 컨테이너(yolo/voice) 이미지 빌드 및 검증 게이트.
#
# host 설치와 독립 동작(Docker 엔진만 있으면 됨).
# 두 애플리케이션 이미지(yolo / voice)를 `builder` 스테이지(:dev-builder 태그 — 소스를 live-mount 하는
# dev 이미지, bringup/docker-compose.dev.yml 로 실행)로 빌드 + "격리 검증(isolated verification)" 수행:
#   (1) 이미지 빌드 성공  (2) secret 위생(docker history 에 자격증명 흔적 없음)  (3) 컨테이너 안 import smoke(가벼운 import 확인).
# 이 단계 = GPU / 마이크 / 카메라 / 모델 가중치 불필요(모듈 import 만 확인).
# torch.cuda.is_available() / 서비스 왕복(round-trip) / od_msg 해시 일치 = host e2e 이후 단계 → 여기서는 미검증.
#
# setup-app.sh 의 컨테이너 단계가 이 스크립트 호출(빌드 + 검증). 아래처럼 단독 실행도 가능.
# Usage: bash containers/build-all.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=resources/config.sh
source "${REPO_ROOT}/resources/config.sh"

# 이미지 좌표(image coordinates) — DOCKERHUB_USER 를 .env 나 환경변수에서 덮어씀. 설정 안 하면 로컬 태그 사용.
: "${DOCKERHUB_USER:=local}"
# dev-builder = Dockerfile 의 `builder` 스테이지(런타임 ENTRYPOINT 없음). 이 태그 문자열은
# docker-compose.dev.yml 과 반드시 일치 필수 — bringup 이 그 override 를 병합해 바로 이 이미지들을 `up`.
YOLO_IMAGE="docker.io/${DOCKERHUB_USER}/ros2-jazzy-yolo:dev-builder"
VOICE_IMAGE="docker.io/${DOCKERHUB_USER}/ros2-jazzy-voice:dev-builder"

# 실제로 쓰는 이미지 좌표를 명시적으로 출력(조용히 기본값으로 넘어가는 것 방지 — 실행 기록(run-manifest) 추적용).
printf 'INFO: build targets — YOLO=%s  VOICE=%s\n' "${YOLO_IMAGE}" "${VOICE_IMAGE}"
if [[ "${DOCKERHUB_USER}" == "local" ]]; then
    printf 'INFO: DOCKERHUB_USER unset → using local dev tags (cannot publish, set coordinates via .env).\n'
fi

TOTAL=5
step() { printf '\n[%d/%d] %s\n' "$1" "${TOTAL}" "$2"; }

#######################################
# 이미지 레이어 히스토리에 자격증명(credential) 흔적이 하나도 없는지 확인(secret 위생).
# 이미지에 한번 구워지면 레지스트리 노출은 비가역 → 반드시 필요.
# Arguments:
#   $1 - 검사할 도커 이미지 태그
# Outputs:
#   흔적 발견 시 stderr 로 실패 메시지
# Returns:
#   흔적 발견 시 1
#######################################
secret_scan() {
    local image="$1"
    if docker history --no-trunc "${image}" | grep -iE 'OPENAI|API_KEY|TOKEN|SECRET|PASSWORD'; then
        echo "  ✗ secret trace found — ${image}" >&2
        return 1
    fi
    echo "  ✓ no secret trace — ${image}"
}

#######################################
# 컨테이너 안에서 가벼운 import 확인(isolated import smoke) 실행.
# builder 스테이지는 런타임 ENTRYPOINT 가 없어서, python 실행 전에 여기서 ROS2 + 오버레이(overlay) +
# venv PYTHONPATH 를 직접 source(containers/entrypoint.sh + dev/bashrc 와 동일한 준비 과정).
# `bash -c 'SCRIPT' "$pyexpr"` 는 pyexpr 를 컨테이너 안 $0 에 묶어 python3 -c "$0" 로 전달
# (따옴표가 중첩되며 깨지는 escaping 문제를 피함).
# Arguments:
#   $1 - 실행할 도커 이미지 태그
#   $2 - python3 -c 로 넘길 파이썬 코드 문자열
#######################################
smoke() {
    local image="$1" pyexpr="$2"
    docker run --rm "${image}" bash -c '
        set +u
        source "/opt/ros/${ROS_DISTRO}/setup.bash"
        [ -f /ws/install/setup.bash ] && source /ws/install/setup.bash
        for sp in /opt/venv/lib/python*/site-packages; do
            [ -d "$sp" ] && export PYTHONPATH="$sp${PYTHONPATH:+:$PYTHONPATH}" && break
        done
        exec python3 -c "$0"
    ' "${pyexpr}"
}

# cobot2 소스는 외부 관리(externalized) — 소스 위치 = 레포가 아니라 ${DSR_WORKSPACE}/src/cobot2.
# Dockerfile 들은 빌드 컨텍스트(REPO_ROOT) 기준으로 cobot_ws/src/cobot2/{yolo_container,voice_container}/... 를 COPY 하므로,
# 검증된 소스를 빌드 컨텍스트 안으로 복사해 둠(/cobot_ws/src/ 경로는 gitignore 됨).
# setup-app 의 obtain_cobot2 가 확인한 바로 그 소스(${DSR_WORKSPACE}/src/cobot2)를 쓰며,
# 레포에 남아있던 오래된(stale) 부분 복사본은 덮어씀.
COBOT2_SRC="${DSR_WORKSPACE}/src/cobot2"
COBOT2_CTX="${REPO_ROOT}/cobot_ws/src/cobot2"
# Dockerfile 들이 COPY 하는 정확한 패키지 디렉토리들(빌드 컨텍스트 기준 경로). yolo_container/voice_container
# 상위 폴더만 보지 말고 이 말단(leaf) 경로들을 직접 확인 — 그래야 소스가 일부만 있을 때(예: od_msg 는 있는데
# object_detection 이 없음) 여기서 바로 크게 실패. 안 그러면 (수 분 걸리는) torch 레이어를 이미 다 받은 뒤에야
# BuildKit 이 알 수 없는 '<path>: not found' 로 터짐. 이 목록은 두 Dockerfile 의 COPY 줄과 항상 일치 필수.
COBOT2_REQUIRED=(
    yolo_container/od_msg
    yolo_container/object_detection
    voice_container/voice_processing
)
missing=()
for rel in "${COBOT2_REQUIRED[@]}"; do
    [[ -d "${COBOT2_SRC}/${rel}" ]] || missing+=("${rel}")
done
if (( ${#missing[@]} )); then
    echo "build-all: cobot2 source incomplete at ${COBOT2_SRC} — missing: ${missing[*]}" >&2
    echo "           Place the full cobot2 source there (setup-app obtain_cobot2) before building." >&2
    exit 1
fi
printf 'INFO: staging cobot2 source %s → %s (build context)\n' "${COBOT2_SRC}" "${COBOT2_CTX}"
rm -rf "${COBOT2_CTX}"
mkdir -p "$(dirname "${COBOT2_CTX}")"
cp -aT "${COBOT2_SRC}" "${COBOT2_CTX}"   # -T: cobot2 그 자체로 복사(남아있는 cobot2/ 폴더 안으로 중첩되지 않게)
# 복사된 빌드 컨텍스트에 그 말단(leaf) 경로들이 실제로 들어있는지 확인 — 복사가 일부만 됐거나
# DSR_WORKSPACE 가 잘못된 경우를, BuildKit 이 거부할 컨텍스트로 torch 다운로드를 낭비하기 전에 잡아냄.
for rel in "${COBOT2_REQUIRED[@]}"; do
    [[ -d "${COBOT2_CTX}/${rel}" ]] || { echo "build-all: staging incomplete — ${COBOT2_CTX}/${rel} absent after copy." >&2; exit 1; }
done

step 1 "build yolo-detection (torch cu${CUDA_VERSION//./} + ultralytics + numpy<2)"
docker build --pull \
    -f "${REPO_ROOT}/containers/yolo-detection/Dockerfile" \
    --target builder \
    --build-arg ROS_DISTRO="${ROS_DISTRO}" \
    --build-arg CUDA_VERSION="${CUDA_VERSION}" \
    -t "${YOLO_IMAGE}" \
    "${REPO_ROOT}"

step 2 "build voice-processing (langchain + openwakeword + numpy<2)"
docker build --pull \
    -f "${REPO_ROOT}/containers/voice-processing/Dockerfile" \
    --target builder \
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
# import 만으로는 불충분: wakeup_word.py 의 Model(.tflite) 로딩은 런타임에만 발생. 그래서 import smoke 를 통과해도
# tflite 백엔드(ai-edge-litert)가 없으면 실제 로봇에서 실패. 여기서 Model 하나를 실제로 만들고 predict 까지 돌려 확인.
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
