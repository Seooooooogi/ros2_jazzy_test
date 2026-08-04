#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/base-install.sh — 재부팅 앞뒤로 도는 시스템 계층 설치.
# 서브커맨드마다 별도 프로세스로 실행되므로 한쪽이 실패해도 다른 쪽에 영향이 없다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
config_assert_set

base_kernel() {

    # 1) HWE 커널 meta + headers meta 설치. --install-recommends 는 modules-extra 도 함께 끌어옴
    #    (recommends 가 빠져 modules-extra 가 누락되는 것이 반쪽짜리 커널의 직접 원인).
    #    apt-get install 은 이미 설치돼 있으면 아무것도 안 함 — 다시 실행해도 안전(멱등).
    sudo apt-get update
    sudo apt-get install -y --install-recommends "${KERNEL_META}" "${KERNEL_HEADERS_META}"

    # 2) 지금 부팅된 커널에 대해 modules-extra / headers 를 명시적으로 보강. HWE meta 는 자기가
    #    추적하는 커널만 보장하므로, 지금 부팅된 커널(설치 시점엔 GA(Ubuntu 기본 제공) 커널일 수 있음)은 따로 보강 필요.
    #    apt-get install 은 이미 설치돼 있으면 아무것도 안 함 — 다시 실행해도 안전(멱등).
    local running
    running="$(uname -r)"
    sudo apt-get install -y "linux-modules-extra-${running}" "linux-headers-${running}"

    # 3) 검증 — wifi 드라이버가 들어있는 net/wireless 모듈 디렉토리가 있는지 확인.
    #    nvidia 게이트와 달리 여기서는 경고만 하고 종료하지 않음: HWE meta 가 방금 새 커널을 설치했다면,
    #    지금 부팅돼 있는 옛 커널에는 wireless 디렉토리가 없는 게 정상일 수 있음(재부팅 후 새 커널에서 해결됨).
    #    실제 차단(게이팅)은 재부팅 복귀 뒤 install.sh 의 초기 체크가 담당.
    if [[ ! -d "/lib/modules/${running}/kernel/drivers/net/wireless" ]]; then
        echo "kernel-baseline: warning — /lib/modules/${running}/.../net/wireless missing." >&2
        echo "  the current kernel (${running}) may be missing modules-extra (affects wifi/USB input)." >&2
    fi

    echo "kernel-baseline: HWE kernel meta + headers + modules-extra guaranteed (current kernel ${running})."
}

_resolve_driver_pkg() {
    dpkg-query -W -f='${db:Status-Abbrev}|${Package}\n' 'nvidia-driver-*' 2>/dev/null \
        | awk -F'|' '$1 ~ /^.i/ {print $2}' \
        | grep -E '^nvidia-driver-[0-9]+(-open|-server|-server-open)?$' | sort -V | tail -n1 || true
}

base_nvidia() {

    # apt 컴포넌트 활성화 — nvidia-modprobe 는 multiverse 에 들어 있어서, multiverse 가 꺼진 설치본
    # (server/minimal)에서는 'unable to locate package nvidia-modprobe' 로 실패.
    # software-properties-common 은 main 에 있어 항상 설치 가능하고, add-apt-repository 는 이미 켜져 있으면 아무 일도 안 함(no-op).
    # (이 단계에 둔 이유: 재시도·재개(resume)마다 다시 보장됨 — 커널 기본 설정 단계가 DONE 으로 skip 돼도 영향 없음.)
    sudo apt-get update
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y universe
    sudo add-apt-repository -y multiverse

    # 빌드 도구 + ubuntu-drivers (apt-get install 은 그 자체로 멱등 — 여러 번 실행해도 결과가 같음).
    sudo apt-get update
    sudo apt-get install -y build-essential gcc ubuntu-drivers-common dkms nvidia-modprobe

    #######################################
    # 설치된 nvidia-driver-NNN 메타 패키지 이름을 찾아 출력.
    # ubuntu-drivers 가 -open / -server 변형을 고를 수 있어 접미사(예: nvidia-driver-595-open)까지 허용.
    # dpkg 의 Status-Abbrev 두 번째 글자가 'i' 면 현재 설치됨. hold 된 패키지는 'hi' 라
    # 'ii' 만 찾으면 놓침(이 스크립트가 스스로 hold 하므로 재실행 시 'hi' 로 보임) → '^.i' 로 매칭.
    # Outputs:
    #   찾은 패키지 이름을 stdout 으로. 없으면 빈 문자열.
    #######################################

    # 드라이버 설치: 이미 설치돼 있으면 skip(재실행 멱등) / 핀 지정돼 있으면 그 버전+플레이버 / 아니면 자동 선택으로 폴백.
    driver_pkg="$(_resolve_driver_pkg)"
    if [[ -n "${driver_pkg}" ]]; then
        echo "nvidia: already installed (${driver_pkg}) — skipping the install step"
    elif [[ -n "${NVIDIA_DRIVER_VERSION}" ]]; then
        # 핀 설치(기본 경로): 드라이버 유저스페이스 + HWE 커널 모듈 메타를 함께 설치.
        # 커널이 업데이트되면 모듈 메타가 맞는 nvidia 모듈을 자동으로 끌어와 짝이 유지됨.
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

    # 드라이버 유저스페이스만 hold 해서 apt upgrade 가 핀을 풀지 못하게 함(이미 hold 면 skip — 멱등).
    # 커널 모듈 메타는 hold 금지: hold 하면 커널 업데이트 추적이 끊겨 다음 커널에서 nvidia 모듈이 빠짐.
    if apt-mark showhold | grep -qx "${driver_pkg}"; then
        echo "nvidia: ${driver_pkg} already held"
    else
        sudo apt-mark hold "${driver_pkg}"
    fi

    echo "nvidia: installed & held -> ${driver_pkg}"

    # --- 재부팅 전 검증 게이트 ---
    # 부팅될 커널에 nvidia 커널 모듈이 실제로 있는지 확인.
    # 재부팅 전에는 $(uname -r) 이 아직 옛 커널일 수 있어서, '지금 돌고 있는 커널' 대신 '부팅될 커널'을 봄.
    # 모듈이 없으면 재부팅 시 디스플레이 드라이버가 없어 화면이 까맣게 죽으므로, 여기서 멈춤
    # (조용히 벽돌 되는 대신 재부팅 전에 크게 실패시킴).
    # 가정: GRUB 기본 부팅 항목은 설치된 커널 중 가장 최신(Ubuntu 기본값 GRUB_DEFAULT=0 + update-grub 정렬 기준).
    # grub-reboot 등으로 특정 옛 커널을 고정해 둔 환경에서는 이 확인이 부정확할 수 있음.
    # /lib/modules 에는 버전 디렉토리 말고 'kernel' 같은 비-버전 항목도 섞여 있을 수 있어, 버전 패턴
    # (숫자로 시작)만 골라 가장 최신을 취함.
    target_kernel="$(find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | grep -E '^[0-9]+\.' | sort -V | tail -n1)"
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

base_docker() {

    local DOCKER_LIST=/etc/apt/sources.list.d/docker.list
    local DOCKER_KEY="${KEYRING_DIR}/docker.asc"

    # 1) 사전 준비 도구(ca-certificates, curl) 설치.
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl

    # 2) 키링 + apt 소스 등록 (add_apt_repo — 멱등: 여러 번 실행해도 결과 동일). 엔진 설치 직전 apt update = 아래 4) 에서 → 여기선 --no-update.
    arch="$(dpkg --print-architecture)"
    add_apt_repo --no-update \
        --mode raw \
        --key-url "https://download.docker.com/linux/ubuntu/gpg" --key-file "${DOCKER_KEY}" \
        --list-file "${DOCKER_LIST}" \
        --list-line "deb [arch=${arch} signed-by=${DOCKER_KEY}] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable"

    # 4) 엔진 설치 (최신 stable, 버전 핀(고정) 안 함). 멱등: docker-ce 가 이미 깔려 있으면 건너뜀.
    #    5) 의 hold 가 버전 밀림 방지 → 다시 실행해도 업그레이드 발생 금지. hold 된 엔진 패키지에
    #    대해 repo 에 더 새로운 후보 버전이 있는 상태에서 `apt-get install` 을 또 돌리면 곧바로 에러 발생:
    #      "E: Held packages were changed and -y was used without --allow-change-held-packages".
    #    정책 = 최신 버전을 한 번만 설치하고 hold — install.sh 를 다시 돌려도(예: --reset 후) hold 된 버전 그대로 유지.
    #    (--allow-change-held-packages 를 붙이면 매 재실행마다 docker 를 업그레이드해서 에러를 "해결"해 버림 → hold 로 버전 고정한 의미 소멸.)
    sudo apt-get update
    if dpkg-query -W -f='${Status}' docker-ce 2>/dev/null | grep -q 'ok installed'; then
        echo "docker: docker-ce already installed — skipping the engine install (hold blocks drift)"
    else
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi

    # 5) 엔진 패키지를 hold(버전 고정) — 이미 hold 돼 있으면 건너뜀.
    for pkg in docker-ce docker-ce-cli containerd.io; do
        if apt-mark showhold | grep -qx "${pkg}"; then
            echo "docker: ${pkg} already held"
        else
            sudo apt-mark hold "${pkg}"
        fi
    done

    # 6) 현재 사용자를 docker 그룹에 추가 (sudo 없이 docker 를 쓸 수 있게). 실제 반영은 재부팅/재로그인 후.
    user="$(id -un)"
    if id -nG "${user}" | tr ' ' '\n' | grep -qx docker; then
        echo "docker: ${user} already in the docker group"
    else
        sudo usermod -aG docker "${user}"
        echo "docker: added ${user} to the docker group (applied after reboot/re-login)"
    fi

    # 7) 검증 — 그룹 변경이 지금 이 셸엔 아직 미반영 → sudo 로 실행. --rm = 실행 끝난 컨테이너 삭제.
    sudo docker run --rm hello-world

    # 8) 확정된 버전을 기록용으로 출력 (COMPATIBILITY.md 갱신할 때 참고).
    echo "docker: installed & held ->"
    docker --version
    docker compose version

    # NVIDIA Container Toolkit(GPU 를 컨테이너 안에서 쓰게 해 주는 도구)은 여기서 미설치 — docker-install 은 a01(step3),
    # 즉 재부팅 전 단계라 GPU 드라이버 커널 모듈 아직 미로드 → 그 상태에서 툴킷 작업 시 실패.
    # 이 작업 = 재부팅 이후 단계에서 nvidia-container-toolkit-install.sh 가 따로 실행(install.sh step14).
}

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

base_vscode() {

    local MS_KEY="${KEYRING_DIR}/packages.microsoft.gpg"
    local VSCODE_LIST=/etc/apt/sources.list.d/vscode.list

    # 1) 사전 준비 도구 + 키링 디렉토리.
    sudo apt-get update
    sudo apt-get install -y wget gpg apt-transport-https ca-certificates
    # 2) 키링 + apt 소스 추가 (add_apt_repo — armored 키를 dearmor(바이너리 GPG 키로 변환), 멱등).
    local arch
    arch="$(dpkg --print-architecture)"
    add_apt_repo \
        --mode dearmor --downloader wget --key-write tee \
        --key-url "https://packages.microsoft.com/keys/microsoft.asc" --key-file "${MS_KEY}" \
        --list-file "${VSCODE_LIST}" \
        --list-line "deb [arch=${arch} signed-by=${MS_KEY}] https://packages.microsoft.com/repos/code stable main"

    # 4) VS Code 설치 (원본은 설치 후 code GUI 를 자동 실행했는데, 비대화/원격 환경에선 멈춰서 제거함).
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
