#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/activate.sh · source 전용
#   비대화형 셸(CI / cron / systemd / 스크립트)에서 ROS2 환경 일괄 활성화
#   앱 Python = 여기서 미취급(voice = host system Python / yolo = 컨테이너 이미지)

_ACT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${_ACT_DIR}/config.sh"

if [[ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
else
    echo "activate: /opt/ros/${ROS_DISTRO}/setup.bash not found — ROS2 ${ROS_DISTRO} not installed?" >&2
fi

# colcon 워크스페이스 overlay source(존재 시)
if [[ -f "${DSR_WORKSPACE}/install/setup.bash" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "${DSR_WORKSPACE}/install/setup.bash"
fi
