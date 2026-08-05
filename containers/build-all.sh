#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# containers/build-all.sh · yolo 앱 컨테이너 이미지 빌드 + 검증 게이트
#   대상 = yolo 이미지 하나(voice = 컨테이너 아님, host 실행)
#   검증 = 빌드 성공 + secret 위생 + 컨테이너 안 import smoke
# Usage: bash containers/build-all.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=resources/config.sh
source "${REPO_ROOT}/resources/config.sh"

# 이미지 좌표(DOCKERHUB_USER 미설정 → 로컬 태그)
: "${DOCKERHUB_USER:=local}"
# dev-builder = Dockerfile 의 builder 스테이지(docker-compose.dev.yml 과 일치 필수)
YOLO_IMAGE="docker.io/${DOCKERHUB_USER}/ros2-jazzy-yolo:dev-builder"

# 실제 사용 이미지 좌표 명시 출력
printf 'INFO: build target — YOLO=%s\n' "${YOLO_IMAGE}"
if [[ "${DOCKERHUB_USER}" == "local" ]]; then
    printf 'INFO: DOCKERHUB_USER unset → using local dev tag (cannot publish, set coordinates via .env).\n'
fi

TOTAL=3
step() { printf '\n[%d/%d] %s\n' "$1" "${TOTAL}" "$2"; }

# 이미지 레이어 히스토리의 자격증명 흔적 부재 확인
secret_scan() {
    local image="$1"
    # 유출 판정 대상 = 값 대입 흔적(NAME=값) 또는 sk- 리터럴
    if docker history --no-trunc "${image}" \
        | grep -iE '(API_?KEY|TOKEN|SECRET|PASSWD|PASSWORD)[[:space:]]*=[[:space:]]*[^[:space:]]|sk-[A-Za-z0-9_-]{16,}'; then
        echo "  ✗ secret trace found — ${image}" >&2
        return 1
    fi
    echo "  ✓ no secret trace — ${image}"
}

# 컨테이너 안 가벼운 import 확인(ROS2 + 오버레이 source 후 python3 -c)
smoke() {
    local image="$1" pyexpr="$2"
    docker run --rm "${image}" bash -c '
        set +u
        source "/opt/ros/${ROS_DISTRO}/setup.bash"
        [ -f /ws/install/setup.bash ] && source /ws/install/setup.bash
        exec python3 -c "$0"
    ' "${pyexpr}"
}

# cobot2 소스 = 레포 아님, ${DSR_WORKSPACE}/src/cobot2 에서 빌드 컨텍스트로 복사
COBOT2_SRC="${DSR_WORKSPACE}/src/cobot2"
COBOT2_CTX="${REPO_ROOT}/cobot_ws/src/cobot2"
# yolo Dockerfile 이 COPY 하는 말단 패키지 경로(그 COPY 줄과 일치 필수)
COBOT2_REQUIRED=(
    yolo_container/od_msg
    yolo_container/object_detection
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
# 복사된 빌드 컨텍스트의 말단 경로 실재 여부 확인
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

step 2 "secret hygiene scan (docker history)"
secret_scan "${YOLO_IMAGE}"

step 3 "isolated import smoke — yolo (no GPU/model needed)"
smoke "${YOLO_IMAGE}" \
"import torch, torchvision, ultralytics, cv2, numpy
from od_msg.srv import SrvDepthPosition
import object_detection.yolo, object_detection.realsense, object_detection.detection
assert numpy.__version__.startswith('1.'), numpy.__version__
print('  yolo import OK — numpy', numpy.__version__)"

printf '\n✅ build gate PASS — yolo image built + secret hygiene + import smoke passed.\n'
printf '   GPU runtime / service round-trip / od_msg hash consistency are verified after host e2e (out of scope for this stage).\n'
