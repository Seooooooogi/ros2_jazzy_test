#!/usr/bin/env bash
# =============================================================
#  ros2_jazzy_test — ROS2 Jazzy workstation installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# dev workspace creation — copy the repo cobot2_ws container packages into the host's ~/yolo_ws·~/voice_ws.
# docker-compose.dev.yml bind-mounts this path (${WS}/src) to the container /ws/src → code edits reflect immediately.
#
# A separate workspace, so you can edit/debug freely there and manually port changes back to share with the repo.
# (A symlink points to a host path inside the docker bind-mount and breaks in the container, so we use copy.)
#
# Idempotent: an already-present package directory is skipped (protects edited copies). Overwrite with --force.
# Usage: bash containers/dev-ws-setup.sh [--force]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=resources/config.sh
source "${REPO_ROOT}/resources/config.sh"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

SRC="${REPO_ROOT}/cobot2_ws"

# "targetWS|packages...". For yolo, object_detection imports od_msg.srv, so copy it together.
ENTRIES=(
    "${YOLO_WS}|od_msg object_detection"
    "${VOICE_WS}|voice_processing"
)
TOTAL="${#ENTRIES[@]}"

n=0
for entry in "${ENTRIES[@]}"; do
    n=$((n + 1))
    IFS='|' read -r ws pkglist <<< "${entry}"
    read -ra pkgs <<< "${pkglist}"
    printf '[%d/%d] %s\n' "${n}" "${TOTAL}" "${ws}"
    mkdir -p "${ws}/src"
    for pkg in "${pkgs[@]}"; do
        dest="${ws}/src/${pkg}"
        if [[ -e "${dest}" && "${FORCE}" -ne 1 ]]; then
            echo "  · ${pkg}: already exists — skip (overwrite with --force)"
            continue
        fi
        rm -rf "${dest}"
        cp -r "${SRC}/${pkg}" "${dest}"
        echo "  ✓ copied ${pkg}"
    done
done

echo
echo "✅ dev workspace ready."
echo "  build: docker compose -f ${REPO_ROOT}/containers/docker-compose.yml -f ${REPO_ROOT}/containers/docker-compose.dev.yml build"
echo "  start: docker compose -f ${REPO_ROOT}/containers/docker-compose.yml -f ${REPO_ROOT}/containers/docker-compose.dev.yml up -d yolo-detection"
echo "  enter: docker exec -it yolo-detection bash   # inside: colcon build --symlink-install && ros2 run object_detection object_detection"
