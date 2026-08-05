#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/base-install.sh · 재부팅 앞뒤로 도는 시스템 계층 설치
#   대상 = 커널 / NVIDIA / Docker / ROS2 / VS Code
#   서브커맨드마다 별도 프로세스 실행 → 한쪽 실패가 다른 쪽에 무영향
# ros2_desktop() / ros2_extras() 원본
#   Tiryoh/ros2_setup_scripts_ubuntu (Apache-2.0)
#   ROS2 공식 문서 (CC-BY-4.0)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
config_assert_set

# HWE 커널 meta + headers + modules-extra 를 한 세트로 정렬(커널 이미지 단독 설치 → wifi + 일부 USB 입력 드라이버 누락 상태로 부팅)
base_kernel() {

    # 1) HWE 커널 meta + headers meta
    sudo apt-get update
    sudo apt-get install -y --install-recommends "${KERNEL_META}" "${KERNEL_HEADERS_META}"

    # 2) 현재 부팅된 커널의 modules-extra / headers 별도 보강
    local running
    running="$(uname -r)"
    if [[ -d "/lib/modules/${running}/kernel/drivers/net/wireless" ]]; then
        echo "kernel: extra modules already present for ${running} — installing headers only."
        sudo apt-get install -y "linux-headers-${running}"
    else
        sudo apt-get install -y "linux-modules-extra-${running}" "linux-headers-${running}"
    fi

    # 3) 검증 = wifi 드라이버가 든 net/wireless 모듈 디렉토리 확인
    if [[ ! -d "/lib/modules/${running}/kernel/drivers/net/wireless" ]]; then
        echo "kernel: warning — /lib/modules/${running}/.../net/wireless missing." >&2
        echo "  the current kernel (${running}) may be missing modules-extra (affects wifi/USB input)." >&2
    fi

    echo "kernel: HWE kernel meta + headers + modules-extra guaranteed (current kernel ${running})."
}

# 설치된 nvidia-driver-NNN 메타 패키지 이름 탐색 후 출력(없으면 빈 문자열)
_resolve_driver_pkg() {
    dpkg-query -W -f='${db:Status-Abbrev}|${Package}\n' 'nvidia-driver-*' 2>/dev/null \
        | awk -F'|' '$1 ~ /^.i/ {print $2}' \
        | grep -E '^nvidia-driver-[0-9]+(-open|-server|-server-open)?$' | sort -V | tail -n1 || true
}

# NVIDIA 드라이버 = 지정 버전 설치 + hold 고정
base_nvidia() {
    sudo apt-get update
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y universe
    sudo add-apt-repository -y multiverse

    # 빌드 도구 + ubuntu-drivers (DKMS = 커널 교체 시마다 드라이버 모듈을 자동 재빌드하는 구조)
    sudo apt-get update
    sudo apt-get install -y build-essential gcc ubuntu-drivers-common dkms nvidia-modprobe

    # 드라이버 설치 분기(기설치 → skip / 버전 지정 → 그 버전 / 그 외 → 자동 선택)
    driver_pkg="$(_resolve_driver_pkg)"
    if [[ -n "${driver_pkg}" ]]; then
        echo "nvidia: already installed (${driver_pkg}) — skipping the install step"
    elif [[ -n "${NVIDIA_DRIVER_VERSION}" ]]; then
        # 드라이버 유저스페이스 + 커널 모듈 메타 동시 설치
        pin_pkg="nvidia-driver-${NVIDIA_DRIVER_VERSION}${NVIDIA_DRIVER_FLAVOR}"
        module_meta="linux-modules-nvidia-${NVIDIA_DRIVER_VERSION}${NVIDIA_DRIVER_FLAVOR}-${KERNEL_META#linux-}"
        echo "nvidia: pin install ${pin_pkg} (+ kernel-module meta ${module_meta})"
        sudo apt-get install -y "${pin_pkg}" "${module_meta}"
        driver_pkg="$(_resolve_driver_pkg)"
    else
        echo "nvidia: NVIDIA_DRIVER_VERSION unset — falling back to ubuntu-drivers auto-selection (non-deterministic)" >&2
        echo "  warning: the fallback path does not install the kernel-module meta (linux-modules-nvidia-...-generic-hwe-24.04)." >&2
        echo "  After the next kernel update, check 'dkms status' / nvidia module loading." >&2
        sudo ubuntu-drivers install
        driver_pkg="$(_resolve_driver_pkg)"
    fi

    if [[ -z "${driver_pkg}" ]]; then
        echo "nvidia: could not find an installed nvidia-driver-NNN package" >&2
        exit 1
    fi

    if apt-mark showhold | grep -qx "${driver_pkg}"; then
        echo "nvidia: ${driver_pkg} already held"
    else
        sudo apt-mark hold "${driver_pkg}"
    fi

    echo "nvidia: installed & held -> ${driver_pkg}"

    # --- 재부팅 전 검증 게이트 ---
    # 부팅될 커널 = 설치된 것 중 최신
    target_kernel="$(find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | grep -E '^[0-9]+\.' | sort -V | tail -n1)"
    # 그 커널의 nvidia 커널 모듈 실재 여부 확인
    if find "/lib/modules/${target_kernel}" -name 'nvidia.ko*' 2>/dev/null | grep -q .; then
        echo "nvidia: verification OK — the to-be-booted kernel (${target_kernel}) has the nvidia kernel module."
        echo "nvidia: applying requires a reboot (handled after a confirm in a01's reboot step)."
    else
        echo "nvidia: verification failed — the to-be-booted kernel (${target_kernel}) lacks nvidia.ko." >&2
        echo "  Rebooting now could yield a black screen (no display driver), so we stop." >&2
        echo "  Check: 'dkms status' / 'dpkg -l linux-modules-nvidia-*' / /var/log/apt/term.log" >&2
        exit 1
    fi
}

# Docker 엔진 설치 + 현재 사용자 docker 그룹 추가
base_docker() {

    local DOCKER_LIST=/etc/apt/sources.list.d/docker.list
    local DOCKER_KEY="${KEYRING_DIR}/docker.asc"

    # 1) 사전 준비 도구 설치
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl

    # 2) 키링 + apt 소스 등록
    arch="$(dpkg --print-architecture)"
    add_apt_repo --no-update \
        --mode raw \
        --key-url "https://download.docker.com/linux/ubuntu/gpg" --key-file "${DOCKER_KEY}" \
        --list-file "${DOCKER_LIST}" \
        --list-line "deb [arch=${arch} signed-by=${DOCKER_KEY}] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable"

    # 4) 엔진 설치
    sudo apt-get update
    if dpkg-query -W -f='${Status}' docker-ce 2>/dev/null | grep -q 'ok installed'; then
        echo "docker: docker-ce already installed — skipping the engine install (hold blocks drift)"
    else
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi

    # 5) 엔진 패키지 버전 고정
    for pkg in docker-ce docker-ce-cli containerd.io; do
        if apt-mark showhold | grep -qx "${pkg}"; then
            echo "docker: ${pkg} already held"
        else
            sudo apt-mark hold "${pkg}"
        fi
    done

    # 6) 현재 사용자 docker 그룹 추가

    user="$(id -un)"
    if id -nG "${user}" | tr ' ' '\n' | grep -qx docker; then
        echo "docker: ${user} already in the docker group"
    else
        sudo usermod -aG docker "${user}"
        echo "docker: added ${user} to the docker group (applied after reboot/re-login)"
    fi

    # 7) 검증
    sudo docker run --rm hello-world

    # 8) 실제 설치 버전 기록용 출력
    echo "docker: installed & held ->"
    docker --version
    docker compose version

}

# ROS2 desktop 설치
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

    # --- rosdep (init = 머신당 1회만 가능) ---
    if [[ ! -e /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
        sudo rosdep init
    fi
    rosdep update

    # --- ~/.bashrc 자동 source ---
    local bashrc="${HOME}/.bashrc"
    grep -qF "source /opt/ros/${ROS_DISTRO}/setup.bash" "${bashrc}" \
        || echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> "${bashrc}"
    grep -qF "source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash" "${bashrc}" \
        || echo "source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash" >> "${bashrc}"
    grep -qF "export ROS_LOCALHOST_ONLY=1" "${bashrc}" \
        || echo "# export ROS_LOCALHOST_ONLY=1" >> "${bashrc}"

    # --- smoke source ---
    if [[ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
        set +u
        # shellcheck disable=SC1090,SC1091
        source "/opt/ros/${ROS_DISTRO}/setup.bash"
        set -u
    fi

    echo "ros2-desktop: success installing ROS2 ${ROS_DISTRO}"
}

# ROS2 extras = robot/control 패키지 + Gazebo Harmonic
ros2_extras() {
    sudo apt-get update

    # DSR / robot 빌드가 요구하는 기반 라이브러리
    sudo apt-get install -y git libpoco-dev libyaml-cpp-dev dbus-x11

    # robot / control 스택
    sudo apt-get install -y \
        "ros-${ROS_DISTRO}-control-msgs" \
        "ros-${ROS_DISTRO}-realtime-tools" \
        "ros-${ROS_DISTRO}-xacro" \
        "ros-${ROS_DISTRO}-joint-state-publisher-gui" \
        "ros-${ROS_DISTRO}-ros2-control" \
        "ros-${ROS_DISTRO}-ros2-controllers" \
        "ros-${ROS_DISTRO}-moveit-msgs"

    # lint / launch 유틸리티
    sudo apt-get install -y \
        "ros-${ROS_DISTRO}-ament-lint-common" \
        "ros-${ROS_DISTRO}-yaml-cpp-vendor" \
        "ros-${ROS_DISTRO}-ros2launch" \
        "ros-${ROS_DISTRO}-ament-pep257"

    # Gazebo Harmonic (ros_gz 메타 패키지 = sim/bridge/image/interfaces 동반 설치)
    sudo apt-get install -y "ros-${ROS_DISTRO}-ros-gz"

    echo "ros2-extras: success installing ROS2 ${ROS_DISTRO} extras (robot/control + Gazebo Harmonic)"
}

# VS Code 설치
base_vscode() {

    local MS_KEY="${KEYRING_DIR}/packages.microsoft.gpg"
    local VSCODE_LIST=/etc/apt/sources.list.d/vscode.list

    # 1) 사전 준비 도구
    sudo apt-get update
    sudo apt-get install -y wget gpg apt-transport-https ca-certificates
    # 2) 키링 + apt 소스 추가
    local arch
    arch="$(dpkg --print-architecture)"
    add_apt_repo \
        --mode dearmor --downloader wget --key-write tee \
        --key-url "https://packages.microsoft.com/keys/microsoft.asc" --key-file "${MS_KEY}" \
        --list-file "${VSCODE_LIST}" \
        --list-line "deb [arch=${arch} signed-by=${MS_KEY}] https://packages.microsoft.com/repos/code stable main"

    # 4) VS Code 설치
    sudo apt-get install -y code

    echo "vscode: success installing Visual Studio Code"
}

case "${1:?base-install: subcommand required (kernel|nvidia|docker|ros2-desktop|ros2-extras|vscode)}" in
    kernel)       base_kernel ;;
    nvidia)       base_nvidia ;;
    docker)       base_docker ;;
    ros2-desktop) ros2_desktop ;;
    ros2-extras)  ros2_extras ;;
    vscode)       base_vscode ;;
    *) echo "base-install: unknown subcommand '$1'" >&2; exit 2 ;;
esac
