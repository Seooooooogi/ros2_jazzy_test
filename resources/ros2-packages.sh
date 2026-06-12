#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/ros2-packages.sh — ROS2 ${ROS_DISTRO} 패키지 설치 (a01 step 4-5).
#
# 두 서브커맨드를 한 파일로 묶되 각각 별도 step·별도 프로세스(bash ros2-packages.sh <sub>)로
# 실행한다 — set -euo 진입점 분리 + run_step 진행률/resume key 가 서브커맨드마다 독립.
#   desktop : ROS2 desktop 코어 (apt repo/keyring + desktop 메타 + rosdep init + bashrc).
#   extras  : 로봇/control 스택 + Gazebo Harmonic (desktop 선행 전제).
#
# backup/ros2-humble-desktop-main.sh / backup/ros2-install.sh 의 jazzy/noble 마이그레이션.
#   원작: Tiryoh/ros2_setup_scripts_ubuntu (Apache-2.0), ROS2 docs (CC-BY-4.0).
# 공통 변경점:
#   - distro/OS 를 config.sh 단일 진실 소스에서 (${ROS_DISTRO}/${UBUNTU_CODENAME}).
#   - apt key 를 /usr/share/keyrings → /etc/apt/keyrings 로 통일 (외부 repo 키링 한 경로).
#   - `apt upgrade -y` 제거 (핀 drift 원인, COMPATIBILITY.md). set -euo pipefail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./apt-repo.sh
source "${SCRIPT_DIR}/apt-repo.sh"
config_assert_set

# ROS2 desktop 코어 설치 (구 ros2-desktop-main.sh).
ros2_desktop() {
    local ROS_KEY="${KEYRING_DIR}/ros.gpg"
    local ROS_LIST=/etc/apt/sources.list.d/ros2.list

    # --- OS / 아키텍처 검증 --------------------------------------------------
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

    # --- ROS2 desktop + dev 도구 --------------------------------------------
    sudo apt-get install -y "ros-${ROS_DISTRO}-ament-package" python3-pyqt5 "ros-${ROS_DISTRO}-ament-cmake" libzmq3-dev
    sudo apt-get install -y "ros-${ROS_DISTRO}-desktop"
    sudo apt-get install -y python3-argcomplete python3-colcon-clean
    sudo apt-get install -y python3-colcon-common-extensions
    sudo apt-get install -y python3-rosdep python3-vcstool

    # --- rosdep (init 1회만) -------------------------------------------------
    if [[ ! -e /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
        sudo rosdep init
    fi
    rosdep update

    # --- ~/.bashrc 자동 source (중복 방지 grep 가드) ------------------------
    local bashrc="${HOME}/.bashrc"
    grep -qF "source /opt/ros/${ROS_DISTRO}/setup.bash" "${bashrc}" \
        || echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> "${bashrc}"
    grep -qF "source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash" "${bashrc}" \
        || echo "source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash" >> "${bashrc}"
    grep -qF "export ROS_LOCALHOST_ONLY=1" "${bashrc}" \
        || echo "# export ROS_LOCALHOST_ONLY=1" >> "${bashrc}"

    # --- smoke source (이 서브셸 한정) --------------------------------------
    if [[ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
        set +u
        # shellcheck disable=SC1090,SC1091
        source "/opt/ros/${ROS_DISTRO}/setup.bash"
        set -u
    fi

    echo "ros2-desktop: success installing ROS2 ${ROS_DISTRO}"
}

# ROS2 extras: 로봇/control 패키지 + Gazebo Harmonic (구 ros2-install.sh).
# desktop 코어는 a01 이 먼저 ros2_desktop 으로 설치하므로 여기서는 desktop-main 미호출.
#   - ros-humble-* → ros-${ROS_DISTRO}-* (distro 문자열은 config.sh 단일 소스).
#   - Gazebo: Classic/Fortress (libignition-gazebo6-dev, gazebo-ros-pkgs, gazebo-msgs) 는
#     jazzy 빌드가 없음 (Classic EOL 2025-01). ROS2 Jazzy 권장 Gazebo Harmonic 을
#     packages.ros.org vendor 패키지 `ros-${ROS_DISTRO}-ros-gz` 로 설치 → 별도 OSRF
#     apt repo 와 deprecated `apt-key add` 블록 자체를 삭제.
ros2_extras() {
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
}

case "${1:?ros2-packages: subcommand 필요 (desktop|extras)}" in
    desktop) ros2_desktop ;;
    extras)  ros2_extras ;;
    *) echo "ros2-packages: 알 수 없는 subcommand '$1' (desktop|extras)" >&2; exit 2 ;;
esac
