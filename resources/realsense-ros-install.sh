#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/realsense-ros-install.sh — ROS2 realsense2 래퍼 (a02 step 3).
#
# backup a05-realsense02.sh 의 jazzy 마이그레이션 (래퍼 apt 설치 부분만).
#   - ros-humble-realsense2-* → ros-${ROS_DISTRO}-realsense2-*.
#   - 원본의 glob (`ros-humble-realsense2-*`) 대신 명시 패키지 — 결정적 설치.
#     camera 가 realsense2-camera-msgs 를 의존으로 동반.
#   - rosdep init/update + colcon build 는 a02 colcon-build.sh 로 이동 (중복 제거).
# 순수 설치 본문 — state 호출 없음.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

sudo apt-get update
sudo apt-get install -y \
    "ros-${ROS_DISTRO}-realsense2-camera" \
    "ros-${ROS_DISTRO}-realsense2-description"

echo "success installing ROS2 ${ROS_DISTRO} realsense2 wrapper"
