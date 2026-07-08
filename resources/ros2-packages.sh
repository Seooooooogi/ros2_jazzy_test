#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/ros2-packages.sh — ROS2 ${ROS_DISTRO} 패키지 설치 (a01 step 4-5).
#
# 한 파일에 두 서브커맨드를 담지만, 실행은 각각 별도 프로세스
# (bash ros2-packages.sh <sub>). 서브커맨드마다 set -euo 진입점이 따로 있고, run_step 의
# 진행률·재개(resume) 키도 독립 → 한쪽이 끊겨도 다른 쪽에 영향 없음.
#   desktop : ROS2 desktop 핵심 (apt repo/키링(apt 서명 키) + desktop 메타패키지 + rosdep init + bashrc 등록).
#   extras  : robot/control 스택 + Gazebo Harmonic (desktop 이 먼저 깔려 있다고 가정).
#
# backup/ros2-humble-desktop-main.sh / backup/ros2-install.sh 를 jazzy/noble 로 옮긴 버전.
#   원본: Tiryoh/ros2_setup_scripts_ubuntu (Apache-2.0), ROS2 docs (CC-BY-4.0).
# 공통 변경점:
#   - distro/OS 는 config.sh 한 곳에서만 정의 (${ROS_DISTRO}/${UBUNTU_CODENAME}) → 여기서 가져옴.
#   - apt 키를 /usr/share/keyrings 에서 /etc/apt/keyrings 로 통일 (외부 repo 키링을 한 경로로 모음).
#   - `apt upgrade -y` 제거 (버전 핀이 밀리는 원인, COMPATIBILITY.md 참고). set -euo pipefail 적용.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./apt-repo.sh
source "${SCRIPT_DIR}/apt-repo.sh"
config_assert_set

#######################################
# ROS2 desktop 핵심 설치 (구 ros2-desktop-main.sh).
# OS/아키텍처 확인 → apt repo·키링 등록 → desktop 메타패키지 + 개발 도구 설치
# → rosdep 초기화 → ~/.bashrc 자동 source 등록 순으로 진행.
# Globals:
#   ROS_DISTRO, UBUNTU_CODENAME, KEYRING_DIR, HOME (읽기)
# Outputs:
#   진행 상황·성공 메시지를 stdout 으로 출력.
# Returns:
#   OS 코드네임 또는 아키텍처가 안 맞으면 1 로 종료.
#######################################
ros2_desktop() {
    local ROS_KEY="${KEYRING_DIR}/ros.gpg"
    local ROS_LIST=/etc/apt/sources.list.d/ros2.list

    # --- OS / 아키텍처 확인 ---
    if ! command -v lsb_release >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y curl lsb-release
    fi

    if [[ "$(lsb_release -sc)" == "${UBUNTU_CODENAME}" ]]; then
        echo "OS Check Passed (${UBUNTU_CODENAME})"
    else
        printf '\033[33m%s\033[m\n' "=================================================="
        printf '\033[33m%s\033[m\n' "ERROR: This OS ($(lsb_release -sc)) != ${UBUNTU_CODENAME}"
        printf '\033[33m%s\033[m\n' "=================================================="
        exit 1
    fi

    if ! dpkg --print-architecture | grep -q 64; then
        printf '\033[33m%s\033[m\n' "ERROR: arch ($(dpkg --print-architecture)) not supported (REP-2000)"
        exit 1
    fi

    # --- apt repo + 키링 ---
    sudo apt-get update
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y universe
    sudo apt-get install -y curl gnupg2 lsb-release build-essential

    local arch
    arch="$(dpkg --print-architecture)"
    add_apt_repo \
        --mode raw \
        --key-url "https://raw.githubusercontent.com/ros/rosdistro/master/ros.key" --key-file "${ROS_KEY}" \
        --list-file "${ROS_LIST}" \
        --list-line "deb [arch=${arch} signed-by=${ROS_KEY}] http://packages.ros.org/ros2/ubuntu ${UBUNTU_CODENAME} main"

    # --- ROS2 desktop + 개발 도구 ---
    sudo apt-get install -y "ros-${ROS_DISTRO}-ament-package" python3-pyqt5 "ros-${ROS_DISTRO}-ament-cmake" libzmq3-dev
    sudo apt-get install -y "ros-${ROS_DISTRO}-desktop"
    sudo apt-get install -y python3-argcomplete python3-colcon-clean
    sudo apt-get install -y python3-colcon-common-extensions
    sudo apt-get install -y python3-rosdep python3-vcstool

    # --- rosdep (init 은 최초 1회만) ---
    if [[ ! -e /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
        sudo rosdep init
    fi
    rosdep update

    # --- ~/.bashrc 자동 source (grep 으로 중복 등록 방지) ---
    local bashrc="${HOME}/.bashrc"
    grep -qF "source /opt/ros/${ROS_DISTRO}/setup.bash" "${bashrc}" \
        || echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> "${bashrc}"
    grep -qF "source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash" "${bashrc}" \
        || echo "source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash" >> "${bashrc}"
    grep -qF "export ROS_LOCALHOST_ONLY=1" "${bashrc}" \
        || echo "# export ROS_LOCALHOST_ONLY=1" >> "${bashrc}"

    # --- smoke source (이 subshell 에서만) ---
    if [[ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
        set +u
        # shellcheck disable=SC1090,SC1091
        source "/opt/ros/${ROS_DISTRO}/setup.bash"
        set -u
    fi

    echo "ros2-desktop: success installing ROS2 ${ROS_DISTRO}"
}

#######################################
# ROS2 extras 설치: robot/control 패키지 + Gazebo Harmonic (구 ros2-install.sh).
# desktop 핵심은 a01 이 ros2_desktop 으로 먼저 깔아 둠 → 여기서 desktop-main 은 안 부름.
#   - ros-humble-* → ros-${ROS_DISTRO}-* (distro 문자열은 config.sh 한 곳에서 가져옴).
#   - Gazebo 선택: Classic/Fortress (libignition-gazebo6-dev, gazebo-ros-pkgs, gazebo-msgs) 는
#     jazzy 빌드 없음 (Classic 은 2025-01 지원 종료). → ROS2 Jazzy 권장인 Gazebo Harmonic 을
#     packages.ros.org 벤더 패키지 `ros-${ROS_DISTRO}-ros-gz` 로 설치 → 별도 OSRF apt repo +
#     deprecated 된 `apt-key add` 블록 통째로 제거.
# Globals:
#   ROS_DISTRO (읽기)
# Outputs:
#   성공 메시지를 stdout 으로 출력.
#######################################
ros2_extras() {
    sudo apt-get update

    # 기반 라이브러리 (DSR/robot 빌드의 사전 요구 패키지).
    sudo apt-get install -y git libpoco-dev libyaml-cpp-dev dbus-x11

    # robot / control 스택.
    sudo apt-get install -y \
        "ros-${ROS_DISTRO}-control-msgs" \
        "ros-${ROS_DISTRO}-realtime-tools" \
        "ros-${ROS_DISTRO}-xacro" \
        "ros-${ROS_DISTRO}-joint-state-publisher-gui" \
        "ros-${ROS_DISTRO}-ros2-control" \
        "ros-${ROS_DISTRO}-ros2-controllers" \
        "ros-${ROS_DISTRO}-moveit-msgs"

    # lint / launch 유틸리티.
    sudo apt-get install -y \
        "ros-${ROS_DISTRO}-ament-lint-common" \
        "ros-${ROS_DISTRO}-yaml-cpp-vendor" \
        "ros-${ROS_DISTRO}-ros2launch" \
        "ros-${ROS_DISTRO}-ament-pep257"

    # Gazebo Harmonic (ros_gz 메타 → ros-gz-sim/-bridge/-image/-interfaces + Harmonic 벤더).
    sudo apt-get install -y "ros-${ROS_DISTRO}-ros-gz"

    echo "ros2-extras: success installing ROS2 ${ROS_DISTRO} extras (robot/control + Gazebo Harmonic)"
}

case "${1:?ros2-packages: subcommand required (desktop|extras)}" in
    desktop) ros2_desktop ;;
    extras)  ros2_extras ;;
    *) echo "ros2-packages: unknown subcommand '$1' (desktop|extras)" >&2; exit 2 ;;
esac
