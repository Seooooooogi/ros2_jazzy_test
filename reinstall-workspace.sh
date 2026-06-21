#!/usr/bin/env bash
# =============================================================
#  ros2_jazzy_test — ROS2 Jazzy workstation installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# reinstall-workspace.sh — rebuild ONLY the colcon workspace (~/cobot_ws), without the full install.sh.
#
# Delegates to the two existing install bodies that own the workspace:
#   resources/dsr-project-install.sh  — clone doosan-robot2 (fork) + mirror repo grouped src + DSR deps + emulator
#   resources/colcon-build.sh         — rosdep + colcon build (container-only packages --packages-skip)
# Both source config.sh themselves and are independent of install.sh's step/state machinery, so calling them
# directly is safe. The repo grouped source (cobot1/cobot2) is always re-mirrored fresh (delete-then-copy in
# dsr-project-install.sh), so a rename or source edit in the repo propagates to ~/cobot_ws on every run.
#
# Modes:
#   (default)   incremental — re-mirror source + incremental colcon build. Keeps the doosan-robot2 clone and
#               existing build/install/log. Fastest; use after editing workspace source.
#   --clean     wipe first — remove the doosan-robot2 clone + build/install/log, then fresh clone + full build.
#               Destructive (regenerable), so it asks for confirmation unless --yes is given.
#
# Note: the delegated scripts also (idempotently) re-verify DSR apt deps and re-check the emulator image pull,
# so this may invoke sudo (apt) and the network even in the default mode — same as the main installer's DSR step.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="${SCRIPT_DIR}/resources"

# shellcheck source=resources/config.sh
source "${RESOURCE_DIR}/config.sh"

CLEAN=0
ASSUME_YES=0

usage() {
    cat <<EOF
Usage: bash reinstall-workspace.sh [--clean] [-y|--yes] [-h|--help]

Rebuild only the colcon workspace (${DSR_WORKSPACE}) — not the full 17-step install.sh.

  (no flags)   incremental: re-mirror repo grouped source + incremental colcon build.
  --clean      remove the doosan-robot2 clone + build/install/log first, then fresh clone + full build.
  -y, --yes    skip the --clean confirmation prompt (for non-interactive use).
  -h, --help   show this help and exit.

The delegated DSR step may use sudo (apt) and the network to re-verify deps/emulator, same as install.sh.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)    CLEAN=1 ;;
        -y|--yes)   ASSUME_YES=1 ;;
        -h|--help)  usage; exit 0 ;;
        *) echo "[reinstall] unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

echo "[reinstall] workspace = ${DSR_WORKSPACE} (mode: $([[ ${CLEAN} -eq 1 ]] && echo clean || echo incremental))"

if [[ ${CLEAN} -eq 1 ]]; then
    # Destructive but regenerable (re-clone + rebuild) — confirm before deleting (no silent irreversible wipe).
    if [[ ${ASSUME_YES} -ne 1 ]]; then
        if [[ -t 0 ]]; then
            read -r -p "[reinstall] --clean will rm -rf ${DSR_WORKSPACE}/src/doosan-robot2 and ${DSR_WORKSPACE}/{build,install,log}. Continue? [y/N] " reply
            [[ "${reply}" =~ ^[Yy]$ ]] || { echo "[reinstall] aborted."; exit 1; }
        else
            echo "[reinstall] --clean needs confirmation but no TTY — re-run with --yes to proceed non-interactively." >&2
            exit 1
        fi
    fi
    echo "[reinstall] cleaning: doosan-robot2 clone + build/install/log"
    rm -rf "${DSR_WORKSPACE}/src/doosan-robot2" \
           "${DSR_WORKSPACE}/build" "${DSR_WORKSPACE}/install" "${DSR_WORKSPACE}/log"
fi

echo "[reinstall] [1/2] workspace source (clone + mirror + DSR deps)"
bash "${RESOURCE_DIR}/dsr-project-install.sh"

echo "[reinstall] [2/2] colcon build"
bash "${RESOURCE_DIR}/colcon-build.sh"

echo "[reinstall] done — ${DSR_WORKSPACE} rebuilt. Source it: source ${DSR_WORKSPACE}/install/setup.bash"
