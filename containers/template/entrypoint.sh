#!/usr/bin/env bash
# =============================================================
#  ros2_jazzy_test — ROS2 Jazzy workstation installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# ENTRYPOINT — source the ROS2 environment on every container start, then exec the user command.
set -euo pipefail

# /opt/ros/${ROS_DISTRO}/setup.bash references unset vars and can break under set -u.
# Temporarily disable -u right before the source.
set +u
# shellcheck source=/dev/null
source "/opt/ros/${ROS_DISTRO}/setup.bash"
set -u

exec "$@"
