#!/usr/bin/env bash
# =============================================================
#  ros2_jazzy_test — ROS2 Jazzy workstation installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# setup-app.sh — application layer setup, separate from the base host install (install.sh).
#
# install.sh sets up only the base host environment (OS / NVIDIA / Docker / ROS2 + reboot + VS Code +
# DDS tuning + static IP + corecode + OPENAI key). This script sets up the cobot2 APPLICATION on top:
#
#   workspace : doosan-robot2 driver clone + DSR deps + emulator → verify cobot2 source → RealSense → colcon build.
#   containers: nvidia-container-toolkit → application container images (fetch prebuilt, or --build from source).
#
# The cobot2 application source is NOT shipped by this repo. The user places it at ${DSR_WORKSPACE}/src/cobot2
# (see obtain_cobot2 below — isolated so it can later be swapped for a git clone / tarball fetch). Without it,
# the workspace step fails loud rather than building a partial workspace that only breaks at runtime.
#
# Run after install.sh (and its reboot) completes. Supersedes the old reinstall-workspace.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="${SCRIPT_DIR}/resources"

# shellcheck source=resources/config.sh
source "${RESOURCE_DIR}/config.sh"
config_assert_set

DO_WORKSPACE=1
DO_CONTAINERS=1
CLEAN=0
BUILD=0
ASSUME_YES=0

usage() {
    cat <<EOF
setup-app.sh — set up the cobot2 application (workspace + containers) on top of the base install.sh.

  bash setup-app.sh                 workspace (driver + cobot2 + RealSense + colcon) + containers (toolkit + images + OPENAI key)
  bash setup-app.sh --workspace-only   only the colcon workspace
  bash setup-app.sh --containers-only  only the container layer (toolkit + images + OPENAI key)
  bash setup-app.sh --clean         wipe the doosan-robot2 clone + build/install/log first, then rebuild
                                    (cobot2 source is NOT touched). Asks to confirm unless --yes.
  bash setup-app.sh --build         build the container images from source instead of fetching prebuilt
                                    (requires cobot2 source at ${DSR_WORKSPACE}/src/cobot2 — Docker build context).
  bash setup-app.sh -y, --yes       skip the --clean confirmation (non-interactive).
  bash setup-app.sh -h, --help      this help.

The cobot2 application source is NOT shipped by this repo — place it at ${DSR_WORKSPACE}/src/cobot2 before running.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace-only)  DO_CONTAINERS=0 ;;
        --containers-only) DO_WORKSPACE=0 ;;
        --clean)           CLEAN=1 ;;
        --build)           BUILD=1 ;;
        -y|--yes)          ASSUME_YES=1 ;;
        -h|--help)         usage; exit 0 ;;
        *) echo "[setup-app] unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if [[ ${DO_WORKSPACE} -eq 0 && ${DO_CONTAINERS} -eq 0 ]]; then
    echo "[setup-app] --workspace-only and --containers-only are mutually exclusive." >&2
    exit 2
fi

# progress denominator (purely for the [n/total] display).
TOTAL=0
[[ ${DO_WORKSPACE} -eq 1 ]] && TOTAL=$(( TOTAL + 5 ))   # cobot2-verify + dsr + rs-sdk + rs-ros + colcon
[[ ${DO_CONTAINERS} -eq 1 ]] && TOTAL=$(( TOTAL + 3 ))  # toolkit + images + openai-key
STEP_N=0
step() { STEP_N=$(( STEP_N + 1 )); echo; echo "[${STEP_N}/${TOTAL}] $*"; }

# obtain_cobot2 — get the cobot2 application source into ${DSR_WORKSPACE}/src/cobot2.
# CURRENT POLICY: manual placement by the user — verify presence, fail loud if absent.
# This is the single isolated seam for the source-acquisition policy: to switch to a git clone or a
# tarball fetch later, replace only this function body (e.g. `git clone <url> "${cobot2}"`).
obtain_cobot2() {
    local cobot2="${DSR_WORKSPACE}/src/cobot2"
    if [[ -d "${cobot2}" ]] && find "${cobot2}" -name package.xml -print -quit | grep -q .; then
        echo "setup-app: cobot2 source found at ${cobot2}"
        return 0
    fi
    echo "setup-app: cobot2 application source not found at ${cobot2}" >&2
    echo "           This repo no longer ships cobot2 — place the source there, then re-run:" >&2
    echo "             mkdir -p ${DSR_WORKSPACE}/src && cp -a <cobot2-source> ${cobot2}" >&2
    exit 1
}

do_clean() {
    # Destructive but regenerable (re-clone + rebuild). cobot2 (user-placed) is preserved.
    if [[ ${ASSUME_YES} -ne 1 ]]; then
        if [[ -t 0 ]]; then
            read -r -p "[setup-app] --clean will rm -rf ${DSR_WORKSPACE}/src/doosan-robot2 and ${DSR_WORKSPACE}/{build,install,log} (cobot2 kept). Continue? [y/N] " reply
            [[ "${reply}" =~ ^[Yy]$ ]] || { echo "[setup-app] aborted."; exit 1; }
        else
            echo "[setup-app] --clean needs confirmation but no TTY — re-run with --yes." >&2
            exit 1
        fi
    fi
    echo "[setup-app] cleaning: doosan-robot2 clone + build/install/log (cobot2 kept)"
    rm -rf "${DSR_WORKSPACE}/src/doosan-robot2" \
           "${DSR_WORKSPACE}/build" "${DSR_WORKSPACE}/install" "${DSR_WORKSPACE}/log"
}

do_workspace() {
    step "cobot2 source (verify)";          obtain_cobot2
    step "doosan-robot2 driver + DSR deps"; bash "${RESOURCE_DIR}/dsr-project-install.sh"
    step "RealSense SDK";                   bash "${RESOURCE_DIR}/realsense-install.sh" sdk
    step "RealSense ROS2 wrapper";          bash "${RESOURCE_DIR}/realsense-install.sh" ros
    step "colcon build";                    bash "${RESOURCE_DIR}/colcon-build.sh"
}

do_containers() {
    step "NVIDIA Container Toolkit"
    env ASSUME_YES=1 SKIP_IF_NO_GPU=1 bash "${RESOURCE_DIR}/nvidia-container-toolkit-install.sh"
    if [[ ${BUILD} -eq 1 ]]; then
        step "build container images (from source)"; bash "${SCRIPT_DIR}/containers/build-all.sh"
    else
        step "fetch container images (prebuilt)";     bash "${SCRIPT_DIR}/containers/fetch-images.sh"
    fi
    # OPENAI_API_KEY → repo-root .env (the voice container mounts it). Interactive prompt; empty = skip
    # (editable in .env later). Idempotent: passes through if the key is already set.
    step "OPENAI_API_KEY (.env for the voice container)"; bash "${RESOURCE_DIR}/openai-key-setup.sh"
}

echo "[setup-app] workspace=${DSR_WORKSPACE} | workspace:$([[ ${DO_WORKSPACE} -eq 1 ]] && echo on || echo off) containers:$([[ ${DO_CONTAINERS} -eq 1 ]] && echo on || echo off)$([[ ${CLEAN} -eq 1 ]] && echo ' | clean')$([[ ${BUILD} -eq 1 ]] && echo ' | build')"

[[ ${CLEAN} -eq 1 ]] && do_clean
[[ ${DO_WORKSPACE} -eq 1 ]] && do_workspace
[[ ${DO_CONTAINERS} -eq 1 ]] && do_containers

echo
echo "[setup-app] done."
[[ ${DO_WORKSPACE} -eq 1 ]] && echo "  workspace: source ${DSR_WORKSPACE}/install/setup.bash"
[[ ${DO_CONTAINERS} -eq 1 ]] && echo "  containers: docker images | run via containers/docker-compose.yml"
