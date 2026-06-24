#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# Shared ENTRYPOINT for the Phase 4 application containers (yolo / voice).
# Sources the ROS2 base environment + the colcon overlay (/ws/install), then execs the user command.
# An extension of template/entrypoint.sh — the difference is the one added overlay-source line.
set -euo pipefail

# Both /opt/ros/${ROS_DISTRO}/setup.bash and the overlay setup.bash reference unset vars,
# which can break under set -u. Temporarily disable -u for the source section only.
set +u
# shellcheck source=/dev/null
source "/opt/ros/${ROS_DISTRO}/setup.bash"
# colcon overlay — source it if built into the image (od_msg / object_detection / voice_processing).
if [[ -f /ws/install/setup.bash ]]; then
    # shellcheck source=/dev/null
    source /ws/install/setup.bash
fi
set -u

# Expose the venv (/opt/venv) pip packages (torch/ultralytics/langchain, etc.) on PYTHONPATH.
# colcon build runs before venv creation, so the ament console-script shebang gets fixed to the system python
# (/usr/bin/python3), and that python cannot see the venv site-packages, so launching a node with `ros2 run`
# raises ModuleNotFoundError (e.g. ultralytics). The venv python is a symlink of the system
# python (same interpreter, same version), so just adding the site-packages path makes import work.
for _venv_sp in /opt/venv/lib/python*/site-packages; do
    [[ -d "${_venv_sp}" ]] || continue
    export PYTHONPATH="${_venv_sp}${PYTHONPATH:+:${PYTHONPATH}}"
    break
done

exec "$@"
