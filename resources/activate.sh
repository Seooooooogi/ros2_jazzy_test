#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/activate.sh — 비대화형 셸(CI / cron / systemd / 스크립트)에서 ROS2 환경을 한 번에 켠다.
# 그런 셸은 ~/.bashrc 를 읽지 않아 ros2 / colcon / rclpy 가 그냥은 안 잡힌다. source 전용.
#
# 사용법:
#   source "$(dirname "${BASH_SOURCE[0]}")/activate.sh"
#
# 앱 Python 은 여기서 다루지 않는다 — voice 스택은 host 의 system Python 에 직접 깔려 그대로 보이고,
# yolo 스택은 컨테이너 이미지 안에 있다.

_ACT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${_ACT_DIR}/config.sh"

if [[ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
else
    echo "activate: /opt/ros/${ROS_DISTRO}/setup.bash not found — ROS2 ${ROS_DISTRO} not installed?" >&2
fi

# colcon 워크스페이스 overlay(기본 ROS2 설치 위에 얹는 내 패키지 계층) — 이걸 켜야 `ros2 run` 이
# host 에서 도는 우리 노드(voice_processing 등)를 찾는다. colcon 빌드가 끝난 뒤에만 존재한다.
if [[ -f "${DSR_WORKSPACE}/install/setup.bash" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "${DSR_WORKSPACE}/install/setup.bash"
fi
