#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# containers/lab/verify.sh — Docker 랩(수동 인터랙티브 구축) 자가검증 게이트 (Gate 1).
#
# 학생이 `docker run -it ... → 라이브러리 설치 → colcon build → docker commit` 으로 만든 이미지가
# 자동 빌드본(build-all.sh)과 같은 import 환경인지 대조한다. GPU/카메라/모델 불요 — 모듈 import 만 확인.
#
# build-all.sh 의 smoke() 와 동일 로직: fresh 컨테이너(`docker run --rm`)에서 ROS + /ws/install overlay +
# venv site-packages 를 직접 준비한 뒤 python import smoke 실행. 커밋 이미지엔 ROS overlay·venv 가 자동
# 활성 안 되므로(인터랙티브 세션의 source/activate 는 commit 에 남지 않음) 여기서 매번 준비한다.
# venv 를 PYTHONPATH 로 주입하므로 venv 가 PATH 에 있든(--change ENV PATH) 없든 견고하다.
#
# torch.cuda.is_available() / 서비스 왕복 / od_msg 해시 일치 = 하드웨어 e2e(Gate 2) → 여기선 미검증.
#
# Usage: bash containers/lab/verify.sh [IMAGE_TAG]   (기본 my-yolo:lab)
set -euo pipefail

IMAGE="${1:-my-yolo:lab}"

if ! command -v docker >/dev/null 2>&1; then
    echo "verify: docker 명령을 찾을 수 없음 — Docker 설치 후 실행." >&2
    exit 1
fi
if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    echo "verify: 이미지 없음 — ${IMAGE}" >&2
    echo "        먼저 랩을 따라 'docker commit ... ${IMAGE}' 로 이미지를 만드세요." >&2
    exit 1
fi

echo "[verify] target image: ${IMAGE}"

# `bash -c 'SCRIPT' "$pyexpr"` 는 python 코드를 컨테이너 안 $0 에 묶어 python3 -c "$0" 로 전달
# (따옴표 중첩으로 깨지는 escaping 회피 — build-all.sh smoke 와 동일 패턴). ROS_DISTRO 는 base
# 이미지(ros:jazzy-ros-base-noble)가 ENV 로 구워둔 값을 그대로 사용.
if docker run --rm "${IMAGE}" bash -c '
    set +u
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
    [ -f /ws/install/setup.bash ] && source /ws/install/setup.bash
    for sp in /opt/venv/lib/python*/site-packages; do
        [ -d "$sp" ] && export PYTHONPATH="$sp${PYTHONPATH:+:$PYTHONPATH}" && break
    done
    exec python3 -c "$0"
' "import torch, torchvision, ultralytics, cv2, numpy
from od_msg.srv import SrvDepthPosition
import object_detection.yolo, object_detection.realsense, object_detection.detection
assert numpy.__version__.startswith('1.'), numpy.__version__
print('  import OK — numpy', numpy.__version__)"; then
    echo "[verify] ✅ PASS — ${IMAGE} 는 자동 빌드본과 동일한 import 환경 (torch/torchvision/ultralytics/cv2 + numpy<2 + od_msg + object_detection)."
else
    echo "[verify] ❌ FAIL — 위 traceback 의 import 가 깨졌습니다. 랩 단계(특히 pip numpy<2 재핀 / colcon build --merge-install / docker commit 범위)를 다시 확인하세요." >&2
    exit 1
fi
