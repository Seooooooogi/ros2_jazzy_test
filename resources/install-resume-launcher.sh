#!/usr/bin/env bash
# =============================================================
#  ros2_jazzy_test — ROS2 Jazzy workstation installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# resources/install-resume-launcher.sh — one-shot launcher invoked by GUI autostart after an unattended-install reboot.
# Relaunches install.sh --unattended from the repo location and keeps the terminal open after it exits (to review the result).
# install.sh itself removes the autostart entry on resume entry (one-shot), so it does not re-fire on every login.
#
# Does not use set -e — even if install fails, the terminal must stay open to show the result.
# However, -u (unbound var) and pipefail are applied to surface latent errors.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
bash install.sh --unattended
rc=$?
echo
echo "[resume] install.sh exited (exit ${rc}). Keeping this terminal open so you can review the result."
exec bash
