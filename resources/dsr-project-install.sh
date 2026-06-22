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
#   - clone the ROKEY-SPARK fork's default branch (main = pinned jazzy snapshot). Skip if already
#     cloned (reproducibility — no git pull). The fork pins the version so upstream pushes don't drift it.
#   - workspace = ${DSR_WORKSPACE}(=~/cobot_ws). Mirror the repo's grouped source (cobot_ws/src/cobot1 +
#     cobot2) into src/ so the unified workspace and the container dev bind-mounts (yolo_container/voice_container
#     subdirs) resolve. The CUDA/voice container packages (object_detection / voice_processing) are present
#     but excluded from the HOST build by colcon-build.sh (--packages-skip); pick_and_place_* carry COLCON_IGNORE.
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
# Pinned source: the ROKEY-SPARK fork instead of upstream doosan-robotics/doosan-robot2. The fork's
# default branch (main) is the verified jazzy snapshot (upstream jazzy commit 816ecb5d) — pins the
# version so the install no longer drifts on upstream pushes and survives upstream force-push/deletion.
DSR_REPO_URL="https://github.com/ROKEY-SPARK/doosan-robot2_jazzy.git"

# The host colcon ws mirrors the repo's grouped source: cobot1 (rokey_cobot1) + cobot2
# (robot_control, cobot2_bringup, rokey_cobot2, yolo_container/{od_msg,object_detection}, voice_container/voice_processing,
# pick_and_place_* with COLCON_IGNORE). The whole grouped tree is copied so the container dev bind-mounts
# (yolo_container/voice_container subdirs) resolve; the CUDA/voice container packages (object_detection/voice_processing)
# are present but excluded from the HOST build by colcon-build.sh (--packages-skip) — they run only in their containers.
WS_GROUPS=(cobot1 cobot2)

# 1) workspace src directory.
mkdir -p "${WS_SRC}"

# 2) doosan-robot2 clone (idempotent — skip if .git exists).
if [[ -d "${WS_SRC}/doosan-robot2/.git" ]]; then
    echo "dsr: doosan-robot2 already cloned (skip)"
else
    # Clone the fork's default branch (main = pinned jazzy snapshot). The fork has no 'jazzy' branch,
    # so do NOT pass -b "${DSR_BRANCH}" (it would fail with "Remote branch not found").
    git clone "${DSR_REPO_URL}" "${WS_SRC}/doosan-robot2"
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

# 3) Mirror the repo's grouped source (cobot1 + cobot2) into the ws src (not symlink — so the
#    workspace does not depend on the repo/USB location). The repo is the source of truth, so a re-run
#    re-syncs: delete the existing group dir then copy fresh → re-run safe. doosan-robot2 (cloned above)
#    sits alongside and is untouched (it is not under these group dirs).
#    fail-loud on missing: merely warning would let the build succeed (exit 0) with packages absent and
#    state=DONE, only discovered at runtime via the missing ROS2 topic.
REPO_SRC="${REPO_DIR}/cobot_ws/src"
for grp in "${WS_GROUPS[@]}"; do
    if [[ ! -d "${REPO_SRC}/${grp}" ]]; then
        echo "dsr: repo source group missing — ${REPO_SRC}/${grp}" >&2
        exit 1
    fi
    rm -rf "${WS_SRC:?}/${grp}"
    cp -a "${REPO_SRC}/${grp}" "${WS_SRC}/${grp}"
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
