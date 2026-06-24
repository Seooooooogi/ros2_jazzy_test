#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/ros2-packages.sh — ROS2 ${ROS_DISTRO} package install (a01 step 4-5).
#
# Bundles two subcommands in one file but runs each as a separate step in a separate process
# (bash ros2-packages.sh <sub>) — separate set -euo entry point + independent run_step progress/resume key per subcommand.
#   desktop : ROS2 desktop core (apt repo/keyring + desktop meta + rosdep init + bashrc).
#   extras  : robot/control stack + Gazebo Harmonic (assumes desktop installed first).
#
# jazzy/noble migration of backup/ros2-humble-desktop-main.sh / backup/ros2-install.sh.
#   Originals: Tiryoh/ros2_setup_scripts_ubuntu (Apache-2.0), ROS2 docs (CC-BY-4.0).
# Common changes:
#   - distro/OS from the config.sh single source of truth (${ROS_DISTRO}/${UBUNTU_CODENAME}).
#   - apt key unified from /usr/share/keyrings → /etc/apt/keyrings (one path for external-repo keyrings).
#   - removed `apt upgrade -y` (a pin-drift cause, COMPATIBILITY.md). set -euo pipefail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./apt-repo.sh
source "${SCRIPT_DIR}/apt-repo.sh"
config_assert_set

# ROS2 desktop core install (former ros2-desktop-main.sh).
ros2_desktop() {
    local ROS_KEY="${KEYRING_DIR}/ros.gpg"
    local ROS_LIST=/etc/apt/sources.list.d/ros2.list

    # --- OS / architecture check --------------------------------------------
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

    # --- apt repo + keyring --------------------------------------------------
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

    # --- ROS2 desktop + dev tools -------------------------------------------
    sudo apt-get install -y "ros-${ROS_DISTRO}-ament-package" python3-pyqt5 "ros-${ROS_DISTRO}-ament-cmake" libzmq3-dev
    sudo apt-get install -y "ros-${ROS_DISTRO}-desktop"
    sudo apt-get install -y python3-argcomplete python3-colcon-clean
    sudo apt-get install -y python3-colcon-common-extensions
    sudo apt-get install -y python3-rosdep python3-vcstool

    # --- rosdep (init only once) --------------------------------------------
    if [[ ! -e /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
        sudo rosdep init
    fi
    rosdep update

    # --- ~/.bashrc auto-source (grep guard to avoid duplicates) -------------
    local bashrc="${HOME}/.bashrc"
    grep -qF "source /opt/ros/${ROS_DISTRO}/setup.bash" "${bashrc}" \
        || echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> "${bashrc}"
    grep -qF "source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash" "${bashrc}" \
        || echo "source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash" >> "${bashrc}"
    grep -qF "export ROS_LOCALHOST_ONLY=1" "${bashrc}" \
        || echo "# export ROS_LOCALHOST_ONLY=1" >> "${bashrc}"

    # --- smoke source (this subshell only) ----------------------------------
    if [[ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
        set +u
        # shellcheck disable=SC1090,SC1091
        source "/opt/ros/${ROS_DISTRO}/setup.bash"
        set -u
    fi

    echo "ros2-desktop: success installing ROS2 ${ROS_DISTRO}"
}

# ROS2 extras: robot/control packages + Gazebo Harmonic (former ros2-install.sh).
# The desktop core is installed first by a01 via ros2_desktop, so desktop-main is not called here.
#   - ros-humble-* → ros-${ROS_DISTRO}-* (distro string from the config.sh single source).
#   - Gazebo: Classic/Fortress (libignition-gazebo6-dev, gazebo-ros-pkgs, gazebo-msgs) have no
#     jazzy build (Classic EOL 2025-01). Install the Gazebo Harmonic recommended for ROS2 Jazzy via the
#     packages.ros.org vendor package `ros-${ROS_DISTRO}-ros-gz` → drop the separate OSRF
#     apt repo and the deprecated `apt-key add` block entirely.
ros2_extras() {
    sudo apt-get update

    # Base libraries (prerequisites for the DSR/robot build).
    sudo apt-get install -y git libpoco-dev libyaml-cpp-dev dbus-x11

    # robot / control stack.
    sudo apt-get install -y \
        "ros-${ROS_DISTRO}-control-msgs" \
        "ros-${ROS_DISTRO}-realtime-tools" \
        "ros-${ROS_DISTRO}-xacro" \
        "ros-${ROS_DISTRO}-joint-state-publisher-gui" \
        "ros-${ROS_DISTRO}-ros2-control" \
        "ros-${ROS_DISTRO}-ros2-controllers" \
        "ros-${ROS_DISTRO}-moveit-msgs"

    # lint / launch utilities.
    sudo apt-get install -y \
        "ros-${ROS_DISTRO}-ament-lint-common" \
        "ros-${ROS_DISTRO}-yaml-cpp-vendor" \
        "ros-${ROS_DISTRO}-ros2launch" \
        "ros-${ROS_DISTRO}-ament-pep257"

    # Gazebo Harmonic (ros_gz meta → ros-gz-sim/-bridge/-image/-interfaces + Harmonic vendor).
    sudo apt-get install -y "ros-${ROS_DISTRO}-ros-gz"

    echo "ros2-extras: success installing ROS2 ${ROS_DISTRO} extras (robot/control + Gazebo Harmonic)"
}

case "${1:?ros2-packages: subcommand required (desktop|extras)}" in
    desktop) ros2_desktop ;;
    extras)  ros2_extras ;;
    *) echo "ros2-packages: unknown subcommand '$1' (desktop|extras)" >&2; exit 2 ;;
esac
