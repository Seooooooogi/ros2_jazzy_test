#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# containers/bringup.sh — integrated bringup with RELIABLE container teardown.
#
# Runs the robot driver + camera (cobot2_bringup launch) AND owns the yolo/voice container
# lifecycle here (docker compose up -d) under a shell trap, so Ctrl+C reliably tears the
# containers down.
#
# WHY a wrapper (not the launch): a ROS2 launch OnShutdown handler does NOT start new processes
# during shutdown, so a `docker compose down` registered there never runs on Ctrl+C — the
# containers leak (left Up). Owning compose in this shell with `trap … INT TERM EXIT` guarantees
# teardown whenever the launch exits (verified by reproduction). The launch itself no longer
# touches containers (run it directly for a robot/camera-only session without containers).
#
# Prereq: `bash setup-app.sh` first (builds cobot2_bringup + the overlay, fetches the images).
# Pass launch args straight through:
#   bash containers/bringup.sh                       # virtual(emulator) + camera + containers
#   bash containers/bringup.sh mode:=real            # real robot
#   bash containers/bringup.sh mode:=virtual camera:=false
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE="${SCRIPT_DIR}/docker-compose.yml"

# config.sh fills the env the compose file interpolates (CYCLONEDDS_XML / ROS_DOMAIN_ID / RMW /
# DOCKERHUB_USER / *_TAG) and the voice service's ../.env. Source once — the trap's down reuses it.
set -a
# shellcheck disable=SC1090,SC1091
source "${REPO_DIR}/resources/config.sh"
set +a

# ROS underlay + cobot_ws overlay so `ros2 launch cobot2_bringup` resolves.
# set +u: ROS setup.bash references unbound vars under `set -u`.
set +u
# shellcheck disable=SC1090,SC1091
source "/opt/ros/${ROS_DISTRO}/setup.bash"
if [[ -f "${DSR_WORKSPACE}/install/setup.bash" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "${DSR_WORKSPACE}/install/setup.bash"
fi
set -u

# Containers are owned by THIS shell — tear down on any exit (Ctrl+C / error / normal). Guard so the
# INT/TERM and EXIT traps do not run it twice.
_cleaned=0
cleanup() {
    if [[ "${_cleaned}" -eq 1 ]]; then return 0; fi
    _cleaned=1
    echo "[bringup] stopping application containers (docker compose down)…"
    docker compose -f "${COMPOSE}" down --timeout 5 || true
}
trap cleanup INT TERM EXIT

echo "[bringup] starting application containers (docker compose up -d)…"
docker compose -f "${COMPOSE}" up -d

echo "[bringup] launching robot driver + camera — Ctrl+C tears everything down."
ros2 launch cobot2_bringup bringup_all.launch.py "$@"
