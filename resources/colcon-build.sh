#!/usr/bin/env bash
# =============================================================
#  ros2_jazzy_test — ROS2 Jazzy workstation installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/colcon-build.sh — cobot_ws colcon build (a02 step 4).
#
# A single build after DSR + RealSense install (avoid duplicate builds — the DSR/RealSense child scripts do not build).
# The unified ws src/ (mirrored from the repo by dsr-project-install.sh) contains all grouped packages; the
# host build skips the container-only ones (object_detection / voice_processing, run only in their images) via
# --packages-skip, and pick_and_place_* via their COLCON_IGNORE.
#   - rosdep init is already guarded by a01 ros2-desktop-main.sh — only update here.
#   - --skip-keys=librealsense2: the SDK is a native apt package, not a ROS rosdep key (a02 step2).
#   - incremental build (no rm -rf build install log) — fast on resume.
# Pure install body — no state calls.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

if [[ ! -d "${DSR_WORKSPACE}/src" ]]; then
    echo "colcon-build: ${DSR_WORKSPACE}/src missing — the DSR install step must run first" >&2
    exit 1
fi

# ROS2 environment (avoid the unbound-var issue of setup.bash under set -u).
set +u
# shellcheck disable=SC1090,SC1091
source "/opt/ros/${ROS_DISTRO}/setup.bash"
set -u

# Ensure the CycloneDDS RMW package — config.sh pins the default RMW to cyclonedds, so rmw_cyclonedds_cpp
# must be installed when colcon resolves a package's default RMW (otherwise dsr_msgs2 etc. fail CMake configure with
# "Could not find ROS middleware implementation 'rmw_cyclonedds_cpp'").
# ROS desktop installs only fastrtps and cyclonedds is a separate package, so we install it here as a build prerequisite.
# A dpkg guard skips apt entirely if already present (idempotent + no network needed on resume).
if ! dpkg -s "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp" >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp"
fi

cd "${DSR_WORKSPACE}"

# rosdep: auto-resolve the workspace packages' declarative deps (init was done in a01).
rosdep update
rosdep install --from-paths src --ignore-src --rosdistro "${ROS_DISTRO}" \
    --skip-keys=librealsense2 -y

# colcon build. The unified ws src now also holds the container packages (object_detection / voice_processing)
# for the container dev bind-mounts, but the host cannot run them (torch / openwakeword live only in the
# yolo/voice images) — skip them so the host build stays at host scope (ament_python would "build" them fine,
# but installing unrunnable nodes on the host is misleading). pick_and_place_* carry COLCON_IGNORE (auto-skipped).
colcon build --packages-skip object_detection voice_processing

echo "colcon-build: success building colcon workspace at ${DSR_WORKSPACE}"
