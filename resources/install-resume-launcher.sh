#!/usr/bin/env bash
# =============================================================
#  ros2_jazzy_test — ROS2 Jazzy workstation installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# resources/install-resume-launcher.sh — one-shot launcher invoked by GUI autostart after the step-6 install reboot.
# Relaunches install.sh from the repo location and keeps the terminal open after it exits (to review the result).
# install.sh itself removes the autostart entry on resume entry (one-shot), so it does not re-fire on every login.
#
# Does not use set -e — even if install fails, the terminal must stay open to show the result.
# However, -u (unbound var) and pipefail are applied to surface latent errors.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
bash install.sh
rc=$?
echo
echo "[resume] install.sh exited (exit ${rc}). Keeping this terminal open so you can review the result."
# Restore sane terminal line settings before handing off to the interactive shell — install.sh's
# step heartbeat / sudo prompt can leave the line discipline in a non-default state. (Issue 3 belt-and-suspenders.)
stty sane 2>/dev/null || true
exec bash
