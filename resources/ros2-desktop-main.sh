#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/ros2-desktop-main.sh — ROS2 ${ROS_DISTRO} desktop 코어 설치 (a01 step 3).
#
# backup/ros2-humble-desktop-main.sh 의 jazzy/noble 마이그레이션.
#   원작: Tiryoh/ros2_setup_scripts_ubuntu (Apache-2.0), ROS2 docs (CC-BY-4.0).
# 변경점:
#   - distro/OS 를 config.sh 단일 진실 소스에서 (${ROS_DISTRO}/${UBUNTU_CODENAME}).
#   - apt key 를 /usr/share/keyrings → /etc/apt/keyrings 로 통일 (Hard Rule #7).
#   - `apt upgrade -y` 제거 (핀 drift 원인, COMPATIBILITY.md). set -euo pipefail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

ROS_KEY="${KEYRING_DIR}/ros.gpg"
ROS_LIST=/etc/apt/sources.list.d/ros2.list

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

sudo install -m 0755 -d "${KEYRING_DIR}"
if [[ ! -f "${ROS_KEY}" ]]; then
    sudo curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o "${ROS_KEY}"
    sudo chmod a+r "${ROS_KEY}"
fi

arch="$(dpkg --print-architecture)"
desired="deb [arch=${arch} signed-by=${ROS_KEY}] http://packages.ros.org/ros2/ubuntu ${UBUNTU_CODENAME} main"
if ! { [[ -f "${ROS_LIST}" ]] && grep -qxF "${desired}" "${ROS_LIST}"; }; then
    echo "${desired}" | sudo tee "${ROS_LIST}" >/dev/null
fi
sudo apt-get update

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
bashrc="${HOME}/.bashrc"
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

echo "success installing ROS2 ${ROS_DISTRO}"
