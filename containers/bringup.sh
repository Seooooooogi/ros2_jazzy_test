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
# Prereq: `bash setup-app.sh` first (builds cobot2_bringup + the overlay, builds the dev-builder images).
# Pass launch args straight through:
#   bash containers/bringup.sh                       # virtual(emulator) + camera + containers
#   bash containers/bringup.sh mode:=real            # real robot
#   bash containers/bringup.sh mode:=virtual camera:=false
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# base + dev override → dev-builder images (live-mount + in-container colcon build). up and down MUST use the
# same -f set, so keep it in one array both the trap and the up call reuse.
COMPOSE_ARGS=(-f "${SCRIPT_DIR}/docker-compose.yml" -f "${SCRIPT_DIR}/docker-compose.dev.yml")

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
    docker compose "${COMPOSE_ARGS[@]}" down --timeout 5 || true
}
trap cleanup INT TERM EXIT

# The dev command (docker-compose.dev.yml) is `… ; colcon build ; sleep infinity` — nodes do NOT auto-run, and
# (no set -e in that command) the container stays Up even if the build fails. So key off THIS run's colcon
# completion log, not container state. A file/exe-existence marker would race: the named volume seeds the baked
# /ws/install before the command wipes+rebuilds it. The log is per-container-run, so it has no such race.
wait_build() {
    local svc="$1" deadline=$(( SECONDS + 600 )) logs
    echo "[bringup] waiting for ${svc} colcon build…"
    while (( SECONDS < deadline )); do
        # Command-substitution (not `docker logs | grep -q`): grep -q closes the pipe on first match →
        # SIGPIPE to docker logs → under pipefail the pipeline reports THAT failure, flipping the if false
        # even on a real match. Substituting reads the whole log first, so no pipe to break.
        logs="$(docker logs "${svc}" 2>&1)" || true
        if grep -q 'packages finished' <<<"${logs}"; then
            echo "[bringup] ${svc} build ready."
            return 0
        fi
        sleep 3
    done
    echo "[bringup] timeout: ${svc} build unfinished — see: docker logs ${svc}" >&2
    return 1
}

echo "[bringup] starting application containers (docker compose up -d)…"
docker compose "${COMPOSE_ARGS[@]}" up -d

wait_build yolo-detection
wait_build voice-processing

echo "[bringup] launching yolo/voice nodes inside the dev containers…"
# docker exec is non-interactive → it does NOT auto-source ~/.bashrc, so source the dev bashrc (mounted by the
# dev override at /root/.bashrc) — ROS + overlay + venv PYTHONPATH, the same env an interactive exec gets.
docker exec -d yolo-detection  bash -c 'source /root/.bashrc; exec ros2 run object_detection object_detection'
docker exec -d voice-processing bash -c 'source /root/.bashrc; exec ros2 run voice_processing get_keyword'

echo "[bringup] launching robot driver + camera — Ctrl+C tears everything down."
ros2 launch cobot2_bringup bringup_all.launch.py "$@"
