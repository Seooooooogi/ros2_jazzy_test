#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# containers/entrypoint.sh — yolo 앱 컨테이너 ENTRYPOINT.
# ROS2 기본 환경 + colcon 오버레이(/ws/install) source 후 → 사용자가 넘긴 명령을 exec 로 실행.
# template/entrypoint.sh 확장 — 오버레이 source 한 줄 추가가 유일한 차이.
set -euo pipefail

# /opt/ros/${ROS_DISTRO}/setup.bash 와 오버레이 setup.bash = 둘 다 값이 안 잡힌(unset) 변수 참조.
# set -u(미설정 변수 사용 시 에러) 상태 → 이게 스크립트를 죽임. source 하는 이 구간에서만 잠깐 -u 끔.
set +u
# shellcheck source=/dev/null
source "/opt/ros/${ROS_DISTRO}/setup.bash"
# colcon 오버레이 — 이미지 안에 빌드돼 있으면 source(od_msg / object_detection).
if [[ -f /ws/install/setup.bash ]]; then
    # shellcheck source=/dev/null
    source /ws/install/setup.bash
fi
set -u

# pip 패키지(torch/ultralytics 등)는 --break-system-packages 로 system python 의
# /usr/local/lib/python3.X/dist-packages 에 설치돼 있다. 이 경로는 기본 sys.path 라
# ament 콘솔 스크립트(shebang = /usr/bin/python3)가 그대로 import 한다 → PYTHONPATH 주입 불요.

exec "$@"
