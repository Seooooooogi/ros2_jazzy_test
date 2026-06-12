#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/activate.sh — One-shot ROS2 environment activation for non-interactive
# shells (CI / cron / systemd / scripted runs) where ~/.bashrc auto-source is not
# applied.
# source 전용 라이브러리 — set -euo 를 여기 두지 않는다(호출 진입점이 셸 옵션을 소유).
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/activate.sh"
#   # 이후 ros2 / colcon / rclpy 사용 가능 (system Python).
#
# Application Python (PyTorch / ultralytics / langchain / openai 등) 은 별도(yolo/voice)
# Docker container 안에만 존재 — 본 wrapper 는 그것을 다루지 않는다.

_ACT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${_ACT_DIR}/config.sh"

if [[ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
else
    echo "activate: /opt/ros/${ROS_DISTRO}/setup.bash not found — ROS2 ${ROS_DISTRO} not installed?" >&2
fi
