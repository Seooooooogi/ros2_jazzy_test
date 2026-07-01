#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/activate.sh — One-shot ROS2 environment activation for non-interactive
# shells (CI / cron / systemd / scripted runs) where ~/.bashrc auto-source is not
# applied.
# Source-only library — no `set -euo` here (the calling entry point owns shell options).
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/activate.sh"
#   # ros2 / colcon / rclpy available afterwards (system Python).
#
# Application Python (PyTorch / ultralytics / langchain / openai, etc.) lives only
# inside the separate (yolo/voice) Docker containers — this wrapper does not handle it.

_ACT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${_ACT_DIR}/config.sh"

if [[ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
else
    echo "activate: /opt/ros/${ROS_DISTRO}/setup.bash not found — ROS2 ${ROS_DISTRO} not installed?" >&2
fi
