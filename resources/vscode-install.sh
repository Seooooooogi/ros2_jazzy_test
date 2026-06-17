#!/usr/bin/env bash
# =============================================================
#  ros2_jazzy_test — ROS2 Jazzy workstation installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/vscode-install.sh — Visual Studio Code install (Microsoft apt repo).
#
# Instead of a one-off .deb download, install via the Microsoft apt repo + keyring for apt management (auto updates).
# The repo is codename-independent (stable main) — decoupled from the Ubuntu version.
# keyring is /etc/apt/keyrings/packages.microsoft.gpg + signed-by (no deprecated apt-key).
# Pure install body — no state calls.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./apt-repo.sh
source "${SCRIPT_DIR}/apt-repo.sh"
config_assert_set

MS_KEY="${KEYRING_DIR}/packages.microsoft.gpg"
VSCODE_LIST=/etc/apt/sources.list.d/vscode.list

# 1) prerequisite tools + keyring directory.
sudo apt-get update
sudo apt-get install -y wget gpg apt-transport-https ca-certificates
# 2) keyring + apt source (add_apt_repo — dearmor the armored key, idempotent).
arch="$(dpkg --print-architecture)"
add_apt_repo \
    --mode dearmor --downloader wget --key-write tee \
    --key-url "https://packages.microsoft.com/keys/microsoft.asc" --key-file "${MS_KEY}" \
    --list-file "${VSCODE_LIST}" \
    --list-line "deb [arch=${arch} signed-by=${MS_KEY}] https://packages.microsoft.com/repos/code stable main"

# 4) install VS Code (the original's auto-launch of the `code` GUI hangs on non-interactive/remote → removed).
sudo apt-get install -y code

echo "vscode: success installing Visual Studio Code"
