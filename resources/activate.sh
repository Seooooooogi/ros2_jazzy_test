#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/activate.sh · source 전용
#   비대화형 셸(CI / cron / systemd / 스크립트)에서 ROS2 환경 일괄 활성화
#   그런 셸 = ~/.bashrc 미독해 → ros2 / colcon / rclpy 기본 미인식
#
# 사용법:
#   source "$(dirname "${BASH_SOURCE[0]}")/activate.sh"
#
# 앱 Python = 여기서 미취급
#   voice 스택 = host 의 system Python 직접 설치 → 그대로 가시
#   yolo 스택 = 컨테이너 이미지 안

_ACT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${_ACT_DIR}/config.sh"

if [[ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
else
    echo "activate: /opt/ros/${ROS_DISTRO}/setup.bash not found — ROS2 ${ROS_DISTRO} not installed?" >&2
fi

# colcon 워크스페이스 overlay = 기본 ROS2 설치 위에 얹는 자체 패키지 계층
#   활성화 필요 → `ros2 run` 이 host 구동 노드(voice_processing 등) 탐색 가능
#   존재 시점 = colcon 빌드 완료 후
if [[ -f "${DSR_WORKSPACE}/install/setup.bash" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "${DSR_WORKSPACE}/install/setup.bash"
fi
