#!/usr/bin/env bash
# =============================================================
#  ros2_jazzy_test — ROS2 Jazzy workstation installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/nvidia-container-toolkit-install.sh — NVIDIA Container Toolkit install.
#
# This is the runtime that exposes the host GPU to containers. The in-container CUDA runtime is bundled by the
# PyTorch wheel, so the toolkit's role is to inject the host's driver libraries + /dev/nvidia* into the container.
# docker-compose's deploy.resources.reservations.devices(nvidia) and `docker run --gpus` depend on this
# toolkit + the registered nvidia runtime → without it the yolo container cannot come up with GPU.
#
# Prerequisites: the nvidia driver (nvidia-driver-install.sh) + Docker (docker-install.sh) installed.
# Needed only in a configuration where the containers (yolo/voice) must run on GPU — not needed for a host-only install.
#
# keyring is /etc/apt/keyrings/nvidia-container-toolkit.gpg (signed-by — no deprecated apt-key).
# Standalone run: bash resources/nvidia-container-toolkit-install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# confirm_or_abort_assumable is in interaction.sh (consent for the docker restart).
# shellcheck source=./interaction.sh
source "${SCRIPT_DIR}/interaction.sh"
# shellcheck source=./apt-repo.sh
source "${SCRIPT_DIR}/apt-repo.sh"
config_assert_set

TOOLKIT_LIST=/etc/apt/sources.list.d/nvidia-container-toolkit.list
TOOLKIT_KEY="${KEYRING_DIR}/nvidia-container-toolkit.gpg"

# 0) prerequisite check — fail-loud if the driver + docker are missing (prevents a half install).
#    SKIP_IF_NO_GPU=1 (install.sh integrated flow): a GPU-less host-only machine does not need the toolkit, so
#    treat driver absence as a normal skip rather than an error (mark the step DONE). Standalone default is fail-loud.
if ! command -v nvidia-smi >/dev/null 2>&1; then
    if [[ "${SKIP_IF_NO_GPU:-0}" == "1" ]]; then
        echo "nvidia-toolkit: no nvidia-smi — treating as a GPU-less host-only configuration and skipping."
        exit 0
    fi
    echo "nvidia-toolkit: no nvidia-smi — the nvidia driver must be installed first." >&2
    exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
    echo "nvidia-toolkit: no docker — docker must be installed first." >&2
    exit 1
fi

# 1) prerequisite tools.
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

# 2) keyring + apt source (add_apt_repo — fetch the upstream list and inject signed-by, multi-line cat compare).
#    The update before install is done by 3) below, so --no-update.
add_apt_repo --no-update \
    --mode dearmor --downloader curl --key-write gpg-o \
    --key-url "https://nvidia.github.io/libnvidia-container/gpgkey" --key-file "${TOOLKIT_KEY}" \
    --list-file "${TOOLKIT_LIST}" \
    --list-url "https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list" \
    --list-sed "s#deb https://#deb [signed-by=${TOOLKIT_KEY}] https://#g" \
    --list-cmp cat

# 3) install.
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

# 4) register the docker runtime (idempotent — nvidia-ctk updates /etc/docker/daemon.json).
sudo nvidia-ctk runtime configure --runtime=docker

# 5) apply the runtime — the daemon.json change takes effect after a docker restart. Skip the restart if already up.
#    A docker daemon restart is an irreversible operation, so require explicit consent (automatable via ASSUME_YES=1).
if docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
    echo "nvidia-toolkit: the nvidia runtime is already registered with docker (skipping restart)."
else
    confirm_or_abort_assumable "Restart the docker daemon to apply the nvidia runtime? (running containers will pause briefly)"
    sudo systemctl restart docker
fi

# 6) verify — confirm the runtime is registered.
if ! docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
    echo "nvidia-toolkit: warning — the nvidia runtime is not visible to docker. Check with 'docker info'." >&2
    exit 1
fi
echo "nvidia-toolkit: OK — docker nvidia runtime registered ->"
nvidia-ctk --version | head -1
