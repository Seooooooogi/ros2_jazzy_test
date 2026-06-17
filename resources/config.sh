#!/usr/bin/env bash
# =============================================================
#  ros2_jazzy_test — ROS2 Jazzy workstation installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# resources/config.sh — Single source of truth for distro / version pins.
# Define distro / version strings here in one place only, never hardcoded per script.
# Source-only library — no `set -euo` here (the calling entry point owns shell options).
#
# Usage (from any installer script):
#   source "$(dirname "${BASH_SOURCE[0]}")/config.sh"   # from inside resources/
#   source "$(dirname "$0")/resources/config.sh"        # top-level (install.sh)
#
# This file is never executed directly. Safe to source even under `set -u`.
# Per-variable policy:
#   - distro/OS pins: forced export (`=`). Even if the user shell is polluted with ROS_DISTRO=humble,
#     this project targets a jazzy environment, so it is unconditionally set to jazzy.
#     On the next distro migration only these two lines change (single source of truth).
#   - path/version variables: `:=` pattern (allows env-var override — useful in tests/CI).

# --- Distro / OS (FORCED) -----------------------------------------------
export ROS_DISTRO=jazzy
export UBUNTU_CODENAME=noble

# Force apt non-interactive mode. orchestrate.sh routes install-command stdout to the log file only
# (console gets progress + stderr only), so if dpkg's conffile/interactive prompt goes to stdout
# it waits for input invisibly and the install stalls. noninteractive blocks that path.
export DEBIAN_FRONTEND=noninteractive

# NOTE: the host venv is retired (decision 2026-05-27). Application Python packages
# (PyTorch / ultralytics / langchain / openai, etc.) live only inside the separate (yolo/voice) containers.
# The host owns only system Python (apt) + the colcon workspace.

# --- Repo source-tree root ----------------------------------------------
# This file's (resources/config.sh) parent = repo root. Computed from its own location regardless of
# clone path and exported as the single source of truth. After colcon install, bringup launch cannot
# locate the repo (container compose / config.sh) via __file__, so it references this value instead. Override allowed (`:=`).
: "${ROS2_JAZZY_TEST_REPO:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export ROS2_JAZZY_TEST_REPO

# --- DSR (jazzy branch confirmed active 2026-05-26) ---------------
: "${DSR_BRANCH:=${ROS_DISTRO}}"
: "${DSR_EMULATOR_VERSION:=3.0.1}"
: "${DSR_WORKSPACE:=${HOME}/cobot_ws}"

# --- Phase 4 dev workspace (container code live-mount, docker-compose.dev.yml only) ----
# When the yolo/voice containers run in dev mode, these host subdirectories of the unified
# cobot_ws are bind-mounted to the container /ws/src. The subdirectory itself holds the packages
# (yolo_ws = od_msg + object_detection, voice_ws = voice_processing) — no nested src/, so the mount
# target is the directory itself. The packages are part of the host colcon workspace built by
# dsr-project-install.sh, so there is no separate copy step.
# Unrelated to production (install.sh / docker-compose.yml) — unused unless the dev override runs. Override allowed.
: "${YOLO_WS:=${DSR_WORKSPACE}/src/cobot2_ws/yolo_ws}"
: "${VOICE_WS:=${DSR_WORKSPACE}/src/cobot2_ws/voice_ws}"

# --- Kernel track (HWE) --------------------------------------------------
# Explicitly install the HWE kernel meta so the kernel image + headers + modules-extra are always kept together.
# Without this meta, another package (e.g. the nvidia module) pulls only the kernel image and modules-extra
# (which carries wifi / some USB input drivers) is missing → it boots but loses wifi/USB keyboard:
# a half kernel. Both nvidia and librealsense2-dkms track kernel updates through this headers meta.
# Note: the kernel-module meta computation in nvidia-driver-install.sh relies on stripping the 'linux-' prefix
# from KERNEL_META (linux-generic-hwe-24.04 → generic-hwe-24.04). If you change the prefix format,
# review the module_meta naming there as well.
: "${KERNEL_META:=linux-generic-hwe-24.04}"
: "${KERNEL_HEADERS_META:=linux-headers-generic-hwe-24.04}"

# --- NVIDIA driver -------------------------------------------------------
# Pin the driver explicitly by version + flavor. The old `ubuntu-drivers install` auto-selection
# picked a different driver per machine/time, and that driver pulled in a half HWE kernel without modules-extra
# as a dependency, leading to a black screen (loss of wifi/USB input) on reboot. To deterministically
# reproduce the verified known-good configuration of the work machine, we pin it.
#   install package = nvidia-driver-${NVIDIA_DRIVER_VERSION}${NVIDIA_DRIVER_FLAVOR}
#   FLAVOR = "" (closed, default) or "-open" (open kernel module).
#   closed as default: on Optimus (hybrid) laptops, -open + KMS sometimes fails to bring up the built-in
#   panel display, causing a black screen (gdm session failure), so we pin closed which is more display-stable.
#   Leaving VERSION empty makes nvidia-driver-install.sh fall back to ubuntu-drivers auto-selection
#   (for override — accepting non-determinism).
: "${NVIDIA_DRIVER_VERSION:=595}"
: "${NVIDIA_DRIVER_FLAVOR:=}"
# CUDA major = 12.8 (PyTorch cu128). Not installed on the host (no CUDA consumer among host colcon
# packages) — the only consumer reading this value is the build-arg in the Phase 4 yolo container Dockerfile.
# The pip index forms cu128 as cu${CUDA_VERSION//./}.
# 12.8 chosen due to 12-4 absence in the Noble apt repo + PyTorch wheel availability (cu118/cu126/cu128).
: "${CUDA_VERSION:=12.8}"

# --- Docker --------------------------------------------------------------
# Empty string = docker-install.sh installs the latest stable for noble, then apt-mark hold.
# The version resolved at install time is recorded in docs/COMPATIBILITY.md (not pinned at install).
# User decision 2026-05-28. No code in the system-layer install reads this variable.
: "${DOCKER_VERSION_STRING:=}"

# --- Phase 4 image distribution (downloaded from public Google Drive, then docker load) ----------
# A clean install (install.sh step14) does not build images; it downloads the tar via the public drive file IDs below
# and loads it (fast reproduction). Direct build/verification (image-producing machine) is containers/build-all.sh.
#
# file ID = public-link identifier (not a secret) — fill in after upload. If empty, fetch fails clearly.
# SHA256 = integrity hash of the `docker save` tar. Always pin it in the repo (here) and upload only the tar to the drive
# — fetching the hash from the same source as the tar makes verification meaningless if both are tampered (trusted source = repo).
: "${YOLO_IMAGE_GDRIVE_ID:=1pbWlfFb3d5L6E_S5XrN9_7s_OLsg_YvC}"
: "${VOICE_IMAGE_GDRIVE_ID:=1iKKLyreAawlDVBcFKqXlyNCG0JNnogYp}"
: "${YOLO_IMAGE_SHA256:=4b29263968bbd0b0247d8b71a11660b309ea596d6796bd899ef8d9bb6bf5d73b}"
: "${VOICE_IMAGE_SHA256:=092b8138e14b7568d7dbaeb27c875867b2a16083f4ee6a0c9b2c1658bb9c2d0b}"

# --- State file (resumable re-run, structured format 2026-05-27) ----
: "${STATE_DIR:=${HOME}/.ros2_jazzy_test}"
: "${STATE_FILE:=${STATE_DIR}/state}"

# --- Detailed install log (append-only — never overwrite) ------------------------
# orchestrate.sh appends the full stdout+stderr of each step command here. By default the console shows
# only the [n/total] progress + heartbeat; ALL step output and any warnings/errors go to this file, not the
# console. It lives in the repo root as `install_log` (git-ignored — machine-specific, regenerable, can reach
# tens of MB with torch/colcon). As a resumable re-run it keeps growing; by policy never truncate/rotate it
# (the user cleans up manually if needed). Overridable via the LOG_FILE env var (tests/CI).
# Path resolved from this file's location (resources/config.sh) → repo root, so it is independent of cwd.
: "${LOG_FILE:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install_log}"

# --- apt keyring (unify every external-repo keyring under one path) ----
: "${KEYRING_DIR:=/etc/apt/keyrings}"

# --- ROS2 DDS / RMW (must match between host ↔ container for discovery to work) -----------
# For the host nodes and the yolo/voice containers to see the same topics/services, the RMW must match
# (with Fast-DDS ↔ CycloneDDS mixed, even the same topic is invisible). Pin the standard to CycloneDDS
# so it is deterministic even in a polluted shell. activate.sh loads this value into the host environment, and the
# two docker-compose services reference the same default → both match. When overriding, export the same value before running compose.
#
# Why CycloneDDS: to reliably receive large topics like RealSense raw (one color frame ≈ 2.6MB),
# both the OS socket buffer and the DDS request buffer must be enlarged together, and CycloneDDS
# can explicitly control buffers/interfaces via XML (CYCLONEDDS_URI), enabling deterministic tuning.
# The kernel buffer (sysctl) and XML buffer are a set — dds-tuning.sh installs both.
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"

# CycloneDDS config XML path + URI. dds-tuning.sh detects the install machine's wired NIC and
# renders to this path (a machine-specific artifact, not tracked in the repo). On non-CycloneDDS RMW it is
# ignored, so always exporting it is harmless. For containers, compose mounts this file.
: "${CYCLONEDDS_XML:=${STATE_DIR}/cyclonedds.xml}"
export CYCLONEDDS_URI="${CYCLONEDDS_URI:-file://${CYCLONEDDS_XML}}"

# NIC override for DDS to use (comma-separated allowed). If empty, dds-tuning.sh auto-detects all physical wired NICs
# (excluding wireless/docker/virtual). Specify explicitly only on CI / special networks.
: "${DDS_NETIF:=}"

# --- host ethernet static IP (robot-equipment LAN) ------------------------------
# The last install.sh step (network_static_ip) fixes this IP on the wired NIC via nmcli.
# Robot LAN layout: .1=OnRobot gripper / .100=robot controller / .30=host. It must be on the same
# subnet as the robot/gripper to communicate. No gateway/DNS is set — the internet goes out via wifi, and if
# this connection grabbed the default route the internet would drop (never-default). If HOST_ETH_NETIF is empty, auto-detect.
: "${HOST_ETH_IP:=192.168.1.30}"
: "${HOST_ETH_PREFIX:=24}"
: "${HOST_ETH_NETIF:=}"

# ROS_DOMAIN_ID single source of truth. The host (activate.sh) and the two compose services must see the same
# value for discovery to work. Pinned explicitly so it is deterministic even in an unset shell.
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-42}"

# --- Progress display ([n/total] visualization) ---------------------
# Last-resort fallback for the orchestrate.sh progress denominator (total).
# **The authoritative source is orchestrate.sh** (STAGE_*_COUNT + install_steps_total) — install.sh computes the
# denominator from orchestrate.sh, and this TOTAL_STEPS is used as a fallback only when orchestrate.sh is not sourced.
# So when adding a step, update only the STAGE constants in orchestrate.sh, and just keep this value matched to their sum.
: "${TOTAL_STEPS:=17}"

# --- Self-check ----------------------------------------------------------
# Called by child scripts right after entry to immediately catch missing required variables.
config_assert_set() {
    local var missing=0
    for var in ROS_DISTRO UBUNTU_CODENAME STATE_FILE KEYRING_DIR KERNEL_META KERNEL_HEADERS_META DSR_WORKSPACE RMW_IMPLEMENTATION CYCLONEDDS_XML; do
        if [[ -z "${!var:-}" ]]; then
            echo "config: required variable '$var' is empty" >&2
            missing=1
        fi
    done
    return "$missing"
}
