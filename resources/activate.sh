#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/activate.sh — 비대화형(non-interactive) 셸에서 ROS2 환경 한 번에 활성화.
# ~/.bashrc 자동 source 미적용 실행(CI / cron / systemd / 스크립트 실행)에서도
# ros2 / colcon / rclpy 바로 쓰도록 환경 변수 확보.
# source 전용 라이브러리 — set -euo 를 여기 두지 않는다(호출 진입점이 셸 옵션을 소유).
#
# 사용법:
#   source "$(dirname "${BASH_SOURCE[0]}")/activate.sh"
#   # 이후 ros2 / colcon / rclpy 사용 가능(system Python).
#
# 애플리케이션 Python(PyTorch / ultralytics / langchain / openai 등) = 별도
# (yolo/voice) Docker 컨테이너 안에만 존재 — 이 wrapper 는 다루지 않음.

_ACT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${_ACT_DIR}/config.sh"

if [[ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
else
    echo "activate: /opt/ros/${ROS_DISTRO}/setup.bash not found — ROS2 ${ROS_DISTRO} not installed?" >&2
fi
