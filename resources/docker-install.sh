#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/docker-install.sh — Docker CE install (a01 step 2).
#
# Policy (user decision 2026-05-28):
#   - Install the latest stable docker-ce stack for noble (no pin at install time).
#   - apt-mark hold the engine packages after install (blocks apt upgrade drift).
#   - The resolved version is recorded in docs/COMPATIBILITY.md (the script echoes it at the end).
#   keyring is /etc/apt/keyrings/docker.asc (signed-by — no deprecated apt-key).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./apt-repo.sh
source "${SCRIPT_DIR}/apt-repo.sh"
config_assert_set

DOCKER_LIST=/etc/apt/sources.list.d/docker.list
DOCKER_KEY="${KEYRING_DIR}/docker.asc"

# 1) prerequisite tools.
sudo apt-get update
sudo apt-get install -y ca-certificates curl

# 2) keyring + apt source (add_apt_repo — idempotent). The update before engine install is done by 4) below, so --no-update.
arch="$(dpkg --print-architecture)"
add_apt_repo --no-update \
    --mode raw \
    --key-url "https://download.docker.com/linux/ubuntu/gpg" --key-file "${DOCKER_KEY}" \
    --list-file "${DOCKER_LIST}" \
    --list-line "deb [arch=${arch} signed-by=${DOCKER_KEY}] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable"

# 4) engine install (latest stable, no pin).
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 5) hold engine packages (skip if already held).
for pkg in docker-ce docker-ce-cli containerd.io; do
    if apt-mark showhold | grep -qx "${pkg}"; then
        echo "docker: ${pkg} already held"
    else
        sudo apt-mark hold "${pkg}"
    fi
done

# 6) add the current user to the docker group (run without sudo). Applied after reboot/re-login.
user="$(id -un)"
if id -nG "${user}" | tr ' ' '\n' | grep -qx docker; then
    echo "docker: ${user} already in the docker group"
else
    sudo usermod -aG docker "${user}"
    echo "docker: added ${user} to the docker group (applied after reboot/re-login)"
fi

# 7) verify — the group change is not applied to the current shell, so run via sudo. --rm cleans up the container.
sudo docker run --rm hello-world

# 8) output for recording the resolved version (referenced when updating COMPATIBILITY.md).
echo "docker: installed & held ->"
docker --version
docker compose version

# The NVIDIA Container Toolkit is not installed here — docker-install is a01 (step3), before reboot,
# so the GPU driver kernel module is not yet loaded and the toolkit work would fail in that state.
# It is run separately by nvidia-container-toolkit-install.sh in a post-reboot step (install.sh step14).
