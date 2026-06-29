#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/realsense-install.sh — RealSense install (a02 step 2-3).
#
# Bundles two subcommands in one file but runs each as a separate step in a separate process
# (bash realsense-install.sh <sub>) — separate set -euo entry point + independent run_step progress/resume key per subcommand.
#   sdk : librealsense2 SDK (DKMS kernel module + utils + headers). Includes apt repo/keyring registration.
#   ros : ROS2 realsense2 wrapper packages (camera + description). Assumes the SDK is installed first.
#
# jazzy/noble migration of backup a04-realsense01.sh / a05-realsense02.sh.
# Pure install body — no state calls.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./apt-repo.sh
source "${SCRIPT_DIR}/apt-repo.sh"
config_assert_set

# librealsense2 SDK (former realsense-sdk-install.sh).
#   - In 2025-11 RealSense was spun off from Intel → RealSense AI, swapping the apt repo domain and signing key.
#     The old librealsense.intel.com/.../librealsense.pgp serves the 2018 Intel key (C8B3A55A...), but the
#     noble repo is signed with the new key (...FB0B24895113F120, @realsenseai.com) → the old key fails verification
#     (NO_PUBKEY). The official current method (librealsense/doc/distribution_linux.md) = realsenseai.com
#     domain + .asc (armored) key converted via gpg --dearmor.
#   - keyring ${KEYRING_DIR}/librealsenseai.gpg + signed-by (no deprecated apt-key).
#   - repo codename `lsb_release -cs` → ${UBUNTU_CODENAME} (config single source).
#   - DKMS kernel-module build needs kernel headers → install the HWE headers meta (${KERNEL_HEADERS_META}) +
#     the current kernel headers together. With the meta present, headers are auto-tracked after a kernel update,
#     so the librealsense2-dkms rebuild does not break (missing headers = camera kernel-module build failure).
#   - removed: `apt remove --purge libgtk-3-dev` (irreversible purge / unneeded on noble),
#              auto-launch of `realsense-viewer` (GUI blocking).
realsense_sdk() {
    local RS_KEY="${KEYRING_DIR}/librealsenseai.gpg"
    local RS_LIST=/etc/apt/sources.list.d/librealsenseai.list
    local RS_KEY_URL="https://librealsense.realsenseai.com/Debian/librealsenseai.asc"
    local RS_REPO="https://librealsense.realsenseai.com/Debian/apt-repo"

    # 0) Remove leftover pre-spinoff Intel key/source (if any) — if not cleaned before apt-get update,
    #    the old repo's NO_PUBKEY blocks the first update. This is an artifact this project created, so it is regenerable.
    sudo rm -f /etc/apt/sources.list.d/librealsense.list "${KEYRING_DIR}/librealsense.pgp"

    # 1) prerequisite tools + keyring directory + kernel headers (for the DKMS build — HWE headers meta + current kernel).
    sudo apt-get update
    sudo apt-get install -y curl ca-certificates gnupg apt-transport-https \
        "${KERNEL_HEADERS_META}" "linux-headers-$(uname -r)"
    # 2) keyring + apt source (add_apt_repo — dearmor the armored key, idempotent).
    add_apt_repo \
        --mode dearmor --downloader curl-sSf --key-write tee \
        --key-url "${RS_KEY_URL}" --key-file "${RS_KEY}" \
        --list-file "${RS_LIST}" \
        --list-line "deb [signed-by=${RS_KEY}] ${RS_REPO} ${UBUNTU_CODENAME} main"

    # 4) librealsense2 SDK (kernel DKMS module + utils + headers + debug symbols).
    sudo apt-get install -y \
        librealsense2-dkms \
        librealsense2-utils \
        librealsense2-dev \
        librealsense2-dbg

    echo "realsense-sdk: success installing RealSense librealsense2 SDK (${UBUNTU_CODENAME} apt repo)"
}

# ROS2 realsense2 wrapper (former realsense-ros-install.sh).
#   - ros-humble-realsense2-* → ros-${ROS_DISTRO}-realsense2-*.
#   - explicit packages instead of the original glob (`ros-humble-realsense2-*`) — deterministic install.
#     camera pulls in realsense2-camera-msgs as a dependency.
#   - rosdep init/update + colcon build moved to a02 colcon-build.sh (dedup).
realsense_ros() {
    sudo apt-get update

    # ROS2 binary packages form a synchronized snapshot with loose inter-package deps and no SONAME bumps,
    # so mixing snapshots breaks ABI at dlopen. realsense2_camera then dies with an undefined symbol
    # (diagnostic_updater::Updater::Updater(NodeBaseInterface, ... , double, uint8)) when the installed
    # diagnostic_updater predates the realsense2_camera snapshot: the dependency is loose, so apt does not
    # auto-upgrade the already-installed older diagnostic_updater. Re-sync the installed ROS packages to the
    # current snapshot first so realsense's ABI deps match what the wrapper was built against.
    # Scoped to the ros-${ROS_DISTRO}-* namespace on purpose: a blanket `apt upgrade` is avoided here (it drifts
    # the held docker/nvidia pins), and those packages are outside this glob and held anyway, so this stays pin-safe.
    local ros_installed
    ros_installed="$(dpkg-query -W -f='${db:Status-Status} ${Package}\n' "ros-${ROS_DISTRO}-*" 2>/dev/null \
        | awk '$1 == "installed" { print $2 }' || true)"
    if [[ -n "${ros_installed}" ]]; then
        # shellcheck disable=SC2086  # intentional word-splitting: ros_installed is a newline-separated package list
        sudo apt-get install -y --only-upgrade ${ros_installed}
    fi

    sudo apt-get install -y \
        "ros-${ROS_DISTRO}-realsense2-camera" \
        "ros-${ROS_DISTRO}-realsense2-description"

    echo "realsense-ros: success installing ROS2 ${ROS_DISTRO} realsense2 wrapper"
}

case "${1:?realsense-install: subcommand required (sdk|ros)}" in
    sdk) realsense_sdk ;;
    ros) realsense_ros ;;
    *) echo "realsense-install: unknown subcommand '$1' (sdk|ros)" >&2; exit 2 ;;
esac
