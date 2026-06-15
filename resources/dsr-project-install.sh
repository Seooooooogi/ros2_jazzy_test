#!/usr/bin/env bash
# =============================================================
#  ros2_jazzy_test — ROS2 Jazzy workstation installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/dsr-project-install.sh — Doosan DSR (doosan-robot2) clone + dependencies + emulator (a02 step 1).
#
# jazzy migration + idempotency of backup/dsr-project-install{,_25}.sh.
#   - clone branch -b ${DSR_BRANCH}(=jazzy). Skip if already cloned (reproducibility — no git pull).
#   - workspace = ${DSR_WORKSPACE}(=~/cobot2_ws). Copy only the host packages from the repo cobot2_ws/
#     (robot_control, od_msg, cobot2_bringup) into src/ — the app/container packages
#     (object_detection / voice_processing / pick_and_place_* / rokey) are handled by the separate (yolo/voice) containers,
#     so they are excluded from the host ws. Only packages in src/ are built, naturally limiting the scope.
#     Copy (not symlink): so the workspace does not depend on the repo location — even running from removable
#     media (USB) it does not break when the media is removed. The repo is the source of truth, so a re-run re-syncs from the repo.
#   - emulator: pull the explicit tag doosanrobot/dsr_emulator:${DSR_EMULATOR_VERSION}.
#     The tag is controlled by the config.sh single source (blocks apt/docker latest drift). The upstream
#     install_emulator.sh also only does the same pull, so we pull directly instead of calling it.
#   - rosdep update / colcon build are handled by a02 colcon-build.sh (avoid duplicate builds).
# Pure install body — no state calls (the a02 orchestrator owns the step framing).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"          # repo root (parent of resources/)
WS_SRC="${DSR_WORKSPACE}/src"
DSR_REPO_URL="https://github.com/doosan-robotics/doosan-robot2.git"

# Packages to build in the host colcon ws (CUDA/voice-dependent packages are excluded to the containers).
# cobot2_bringup = the integrated bringup launch package (driver+camera+container startup, excluding robot_control).
HOST_PKGS=(robot_control od_msg cobot2_bringup)

# 1) workspace src directory.
mkdir -p "${WS_SRC}"

# 2) doosan-robot2 clone (idempotent — skip if .git exists).
if [[ -d "${WS_SRC}/doosan-robot2/.git" ]]; then
    echo "dsr: doosan-robot2 already cloned (skip)"
else
    git clone -b "${DSR_BRANCH}" "${DSR_REPO_URL}" "${WS_SRC}/doosan-robot2"
fi

# 2b) doosan-robot2 (jazzy) source-compat patch — fixes two name mismatches in DSR_ROBOT2.py (this distro clone).
#     Both are idempotent (no-op if already correct) → safe to re-run/re-clone.
DSR_IMP_PY="${WS_SRC}/doosan-robot2/dsr_common2/imp/DSR_ROBOT2.py"
if [[ -f "${DSR_IMP_PY}" ]]; then
    # (1) A reference to a non-existent service class 'SetSingularityHandlingForce' (Singular+ity) →
    #     a NameError at module-load time breaks `import DSR_ROBOT2` itself. Align it to the actual class name
    #     'SetSingularHandlingForce' (Singular) that dsr_msgs2 builds.
    if grep -q 'SetSingularityHandlingForce' "${DSR_IMP_PY}"; then
        sed -i 's/SetSingularityHandlingForce/SetSingularHandlingForce/g' "${DSR_IMP_PY}"
        echo "dsr: patched DSR_ROBOT2.py service class name (SetSingularityHandlingForce → SetSingularHandlingForce)"
    fi
    # (2) The service/topic name prefix is empty (''), so the client calls '/<ns>/aux_control/...' while the
    #     actual controller (dsr_controller2) advertises '/<ns>/dsr_controller2/...'.
    #     → no server for that name, so get_current_posj etc. wait forever. Fill the prefix with 'dsr_controller2/'
    #     so the client targets the real server (module level only; excludes the indented class version).
    if grep -qE "^_srv_name_prefix[[:space:]]*=[[:space:]]*''" "${DSR_IMP_PY}"; then
        sed -i -E "s|^_srv_name_prefix([[:space:]]*)=[[:space:]]*''|_srv_name_prefix\1= 'dsr_controller2/'|" "${DSR_IMP_PY}"
        echo "dsr: patched DSR_ROBOT2.py service prefix ('' → 'dsr_controller2/')"
    fi
else
    echo "dsr: DSR_ROBOT2.py missing — patch skipped (verify the clone)" >&2
fi

# 3) Copy the repo host packages into the ws src (not symlink — so the workspace does not depend on the
#    repo/USB location). The repo is the source of truth, so a re-run re-syncs from the repo:
#    delete the existing target (including symlinks created by older versions) and copy fresh → re-run safe.
#    fail-loud on missing: merely warning and moving on would let the build succeed (exit 0) but with the
#    package missing from the workspace and state=DONE, only discovered at runtime via the absent ROS2 topic.
for pkg in "${HOST_PKGS[@]}"; do
    if [[ ! -d "${REPO_DIR}/cobot2_ws/${pkg}" ]]; then
        echo "dsr: host package source missing — ${REPO_DIR}/cobot2_ws/${pkg}" >&2
        exit 1
    fi
    rm -rf "${WS_SRC:?}/${pkg}"
    cp -a "${REPO_DIR}/cobot2_ws/${pkg}" "${WS_SRC}/${pkg}"
done

# 4) apt packages for the DSR build dependency (only DSR-specific ones not in a01 ros2-install.sh / desktop core).
#    The rest of the declarative deps are auto-resolved by rosdep install in colcon-build.sh.
sudo apt-get update
sudo apt-get install -y \
    "ros-${ROS_DISTRO}-velocity-controllers" \
    "ros-${ROS_DISTRO}-eigen3-cmake-module"

# 4b) Runtime Python deps of robot_control (host client) — installed via system Python (apt) as a thin client.
#     This is a container variant, so the home of the app Python (torch/ultralytics/openwakeword) is the yolo/voice containers,
#     but robot_control is a ROS2 node running on the host, so scipy (coordinate transform)/numpy/pymodbus (gripper Modbus)
#     are needed on the host. ament_python does not import at build time so colcon passes, but ros2 run breaks at runtime.
#     apt instead of venv: keeps the host=system Python responsibility and lets ros2 run see them without extra activation.
#     numpy from noble apt (1.26, <2) is enough (no ultralytics on host); pymodbus from noble apt is 3.x
#     (onrobot.py was migrated to the 3.x API).
sudo apt-get install -y \
    python3-numpy python3-scipy python3-pymodbus

# 5) DSR emulator image (explicit tag — docker auto-skips if already present).
docker pull "doosanrobot/dsr_emulator:${DSR_EMULATOR_VERSION}"

echo "dsr: success installing Doosan DSR (${DSR_BRANCH}) + emulator ${DSR_EMULATOR_VERSION}"
