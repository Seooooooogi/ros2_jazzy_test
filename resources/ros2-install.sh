#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/ros2-install.sh — ROS2 extras: 로봇/control 패키지 + Gazebo (a01 step 4).
#
# backup/ros2-install.sh 의 jazzy 마이그레이션. 단, 이제 desktop 코어는 a01 이 먼저
# ros2-desktop-main.sh 로 설치하므로 이 스크립트는 "extras 전용" (desktop-main 미호출).
# 변경점:
#   - ros-humble-* → ros-${ROS_DISTRO}-* (distro 문자열은 config.sh 단일 소스).
#   - Gazebo: Classic/Fortress (libignition-gazebo6-dev, gazebo-ros-pkgs, gazebo-msgs) 는
#     jazzy 빌드가 없음 (Classic EOL 2025-01). ROS2 Jazzy 권장 Gazebo Harmonic 을
#     packages.ros.org vendor 패키지 `ros-${ROS_DISTRO}-ros-gz` 로 설치 → 별도 OSRF
#     apt repo 와 deprecated `apt-key add` 블록 자체를 삭제.
#   - `apt upgrade -y` 제거 (drift). set -euo pipefail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

sudo apt-get update

# 기본 라이브러리 (DSR/robot 빌드 선행).
sudo apt-get install -y git libpoco-dev libyaml-cpp-dev dbus-x11

# 로봇 / control 스택.
sudo apt-get install -y \
    "ros-${ROS_DISTRO}-control-msgs" \
    "ros-${ROS_DISTRO}-realtime-tools" \
    "ros-${ROS_DISTRO}-xacro" \
    "ros-${ROS_DISTRO}-joint-state-publisher-gui" \
    "ros-${ROS_DISTRO}-ros2-control" \
    "ros-${ROS_DISTRO}-ros2-controllers" \
    "ros-${ROS_DISTRO}-moveit-msgs"

# lint / launch 유틸.
sudo apt-get install -y \
    "ros-${ROS_DISTRO}-ament-lint-common" \
    "ros-${ROS_DISTRO}-yaml-cpp-vendor" \
    "ros-${ROS_DISTRO}-ros2launch" \
    "ros-${ROS_DISTRO}-ament-pep257"

# Gazebo Harmonic (ros_gz 메타 → ros-gz-sim/-bridge/-image/-interfaces + Harmonic vendor).
sudo apt-get install -y "ros-${ROS_DISTRO}-ros-gz"

echo "ros2-extras: success installing ROS2 ${ROS_DISTRO} extras (robot/control + Gazebo Harmonic)"
