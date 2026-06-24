#!/usr/bin/env bash
# =============================================================
#  ros2_jazzy_test — ROS2 Jazzy workstation installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# install.sh — single entry point for host workstation setup (full a01~a04 sequence).
#
# Runs prerequisites (kernel/NVIDIA/Docker/ROS2) + robot/camera + VS Code + voice check + DDS tuning +
# NVIDIA Container Toolkit + container-image fetch + static network IP as a single continuous
# sequence ([n/17]). Step definitions are run_stage_a0N in resources/orchestrate.sh.
# Re-run safe: completed steps are auto-skipped per the state file, continuing from where it stopped.
# To force a specific task to re-run, use --reset (full reset) or run resources/<step>.sh directly.
#
# Usage:
#   bash install.sh            run the full sequence (skip completed steps)
#   bash install.sh --status   print the current progress (state)
#   bash install.sh --reset    reset the state (after confirm — re-run all steps)
#   bash install.sh --help
#
# The install reboots once at step 6 to apply the driver/docker group, then auto-resumes on return
# (login) via a one-shot GUI autostart entry — no manual re-run needed (assumes a GUI session). If the
# autostart cannot register (no terminal emulator), re-run 'bash install.sh' after reboot to continue from step 7.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="${SCRIPT_DIR}/resources"

# Do not run directly as root — HOME=/root would put the state / docker group / workspace under /root
# by mistake, never reflecting into the regular user's environment. Children call the needed commands via sudo.
if [[ "$(id -u)" -eq 0 ]]; then
    echo "install: do not run with sudo. Run 'bash install.sh' as a regular user." >&2
    echo "         (the script calls the necessary commands via sudo on its own.)" >&2
    exit 1
fi

# step engine (state + run_step + step definitions) + install UX (confirm + env-load + auto-resume).
# shellcheck source=resources/config.sh
source "${RESOURCE_DIR}/config.sh"
# shellcheck source=resources/orchestrate.sh
source "${RESOURCE_DIR}/orchestrate.sh"
# shellcheck source=resources/interaction.sh
source "${RESOURCE_DIR}/interaction.sh"
config_assert_set
STEPS_TOTAL="$(install_steps_total)"

usage() {
    cat <<'EOF'
install.sh — single entry point for host setup (a01~a04 + DDS tuning + NVIDIA Container Toolkit + container images + static network IP + corecode relocation, 17 steps total)

  bash install.sh             run the full sequence (skip already-completed steps)
  bash install.sh --verbose   also show each step's detailed output + warnings/errors on the console
  bash install.sh --status    print the current progress (state)
  bash install.sh --reset     reset the state (after confirm — re-run all steps)
  bash install.sh --help      this help

The run collects OPENAI_API_KEY + asks one confirm at the start, then proceeds automatically. It reboots
once at step 6 and auto-resumes on return (login) via a one-shot GUI autostart entry — no manual re-run
needed (GUI session required; one sudo password after return). If the autostart cannot register, re-run
'bash install.sh' after reboot to continue. Completed steps are auto-skipped on any re-run.

By default the console shows only the [n/total] progress + per-step elapsed time; ALL detailed output and
any warnings/errors go to install_log in the repo root (not the console). On a step failure a one-line
[FAIL] + the log path is shown. Use --verbose or the VERBOSE=1 environment variable to also show detailed
output on the console.
EOF
}

# Project copyright banner — printed to the console at the start of every actual install run, including the
# auto-resumed terminal after the step-6 reboot, so the attribution is always visible. Goes to stdout
# unconditionally; it is not a per-step output, so the log-routing/quiet console behavior does not apply to it.
print_copyright() {
    cat <<'EOF'
============================================================
 ros2_jazzy_test — ROS2 Jazzy workstation installer
 Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
============================================================
EOF
}

# --verbose/-v is orthogonal to the subcommands, so split it out first into VERBOSE and keep the rest.
# run_step in orchestrate.sh reads VERBOSE in the same shell (export is for the child resource scripts).
VERBOSE="${VERBOSE:-0}"
__args=()
for __a in "$@"; do
    case "$__a" in
        -v|--verbose) VERBOSE=1 ;;
        *) __args+=("$__a") ;;
    esac
done
export VERBOSE
# expansion guard against the empty-array + set -u → unbound-var error (bash<4.4). Do not simplify to "${__args[@]}".
set -- "${__args[@]+"${__args[@]}"}"

# --- argument dispatch (${1:-} required under set -u) ---
case "${1:-}" in
    --status) state_dump; exit 0 ;;
    --reset)
        confirm_or_abort "Reset the state file? (re-runs all steps on reinstall)"
        rm -f "$STATE_FILE"
        echo "install: state reset complete (deleted $STATE_FILE)."
        exit 0
        ;;
    --help|-h) usage; exit 0 ;;
    "") : ;;
    *) echo "install: unknown option '$1'" >&2; usage; exit 2 ;;
esac

# Ensure the detailed-log directory exists before any $LOG_FILE write (advisory warnings / ERR trap below),
# so an overridden LOG_FILE pointing at a not-yet-created dir does not silently drop those early writes.
# Default path (repo root / install_log) → dirname is the repo root, so this is a harmless no-op.
mkdir -p "$(dirname "$LOG_FILE")"

# Show the copyright banner for an actual install run (after the utility subcommands above have exited).
# Unconditional → it appears on the first run and on the auto-resumed terminal after the reboot alike.
print_copyright

# --- preflight: prevent the accident of running halfway in a wrong environment then failing ---
if [[ ! -f /etc/os-release ]]; then
    echo "install: cannot read /etc/os-release — make sure this is an Ubuntu environment." >&2
    exit 1
fi
# shellcheck source=/dev/null
host_codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
if [[ "$host_codename" != "$UBUNTU_CODENAME" ]]; then
    echo "install: this installer targets Ubuntu '$UBUNTU_CODENAME' (current: '${host_codename:-unknown}')." >&2
    exit 1
fi
if ! sudo -v; then
    echo "install: cannot verify sudo privileges. Run as a sudo-capable regular user." >&2
    exit 1
fi

# sudo keepalive — refresh the sudo cache every 60s during long steps (driver/colcon) to avoid re-entry.
# Keeps the auto-resume flow (one sudo password after return) from re-prompting until the end. Cleaned up on exit.
# set +e inside the subshell — so the keepalive does not die silently on a transient sudo -n failure or sleep interrupt.
# It must stay in this script's session so `sudo -n` refreshes the SAME tty timestamp (tty_tickets) the foreground
# script uses — a detached (setsid) session would warm a different ticket and not actually keep it alive.
# The subshell traps its own teardown and kills the in-flight `sleep`: otherwise the EXIT trap below kills only the
# subshell, orphaning the `sleep` child into this script's process group. In the GUI auto-resume terminal that orphan
# would sit in the terminal's foreground process group and block input after the launcher hands off to `exec bash`.
( set +e
  trap 'kill "${_ka_sleep:-0}" 2>/dev/null; exit 0' TERM EXIT
  while kill -0 "$$" 2>/dev/null; do
      sudo -n true 2>/dev/null
      sleep 60 & _ka_sleep=$!
      wait "${_ka_sleep}"
  done ) &
_SUDO_KA_PID=$!
trap 'kill "${_SUDO_KA_PID}" 2>/dev/null || true' EXIT

# Reinforces reporting of an unexpected failure location inside a child body (orthogonal to run_step's step_end_fail).
# One-line console notice + log path only — the failure detail itself is in the log (console stays clean).
trap 'echo "[install] failed: line $LINENO — see ${LOG_FILE}" >&2' ERR

# --- pre-collect credentials + register auto-resume across the step-6 reboot ----------------------------
# First run (before reboot): pre-collect OPENAI_API_KEY + one proceed-confirm + register auto-resume on return.
#   → after the step-6 reboot, step12 (voice) passes non-interactively since the key already exists, and reboot is not re-confirmed.
# Resume (after reboot): remove the autostart entry immediately (one-shot — prevents re-firing on every login). sudo is entered once
#   in this terminal via the sudo -v above.
if step_should_skip a01_reboot; then
    remove_resume_autostart
elif [[ -t 0 ]]; then
    install_collect_secrets "${SCRIPT_DIR}" || true
    confirm_or_abort "The install reboots once midway and auto-continues on return (login) (terminal auto-opens, one sudo password). Continue?"
    register_resume_autostart "${SCRIPT_DIR}"
else
    # Advisory warning → log only (console stays clean). Surfaces in install_log for diagnosis.
    { echo "[install] warning: non-interactive shell — cannot register auto-resume."
      echo "          Run it in a GUI session, or re-run 'bash install.sh' manually after reboot."; } >>"$LOG_FILE"
fi

# --- steps 1~5: prerequisites (a01: kernel baseline / NVIDIA / Docker / ROS2 jazzy / extras) ---
# kernel-baseline before nvidia: the HWE kernel meta + headers + modules-extra must be guaranteed so that
# both the brick (nvidia module pulling a half kernel) and the missing DKMS headers are blocked.
run_stage_a01 0

# --- step 6: reboot boundary (a01) ---
# Cannot be wrapped in run_step: reboot terminates the process, and all subsequent steps (7 onward)
# must run after reboot. Record DONE to disk before reboot so the post-reboot re-run skips this step
# (prevents an infinite reboot loop).
# On confirm-decline / non-interactive abort, DONE is not recorded so a01_reboot stays RUNNING.
# The skip decision looks only at DONE, so the next run asks for reboot again — intended, since consent was not yet given.
if ! step_should_skip a01_reboot; then
    step_begin 6 "${STEPS_TOTAL}" a01_reboot
    # Reboot consent was given by the start confirm above (a tty run) — do not re-ask. A non-interactive
    # first run skipped that confirm with a logged warning and proceeds automatically here.
    echo "[install] prerequisites (kernel/driver/Docker/ROS2) complete — rebooting to apply the driver and docker group."
    step_end_ok
    echo
    echo ">>> Rebooting. It auto-resumes on return (login) — no manual run needed."
    sudo reboot
fi

# Early check after reboot return: confirm the booted kernel has the wifi/USB drivers (modules-extra).
# If it booted into the wrong (half) kernel, warn before proceeding to later steps (RealSense DKMS, etc.).
__running="$(uname -r)"
if [[ ! -d "/lib/modules/${__running}/kernel/drivers/net/wireless" ]]; then
    # Advisory warning → log only (console stays clean). Surfaces in install_log for diagnosis.
    { echo "[install] warning: the current kernel (${__running}) appears to lack modules-extra — wifi/USB input may be missing."
      echo "          Boot a kernel that has modules-extra from GRUB, or see the kernel-module section in docs/TROUBLESHOOTING.md."; } >>"$LOG_FILE"
fi

# --- steps 7~10: robot/camera (a02: DSR + RealSense + colcon build) ---
run_stage_a02 6

# --- step 11: development tools (a03: VS Code) ---
run_stage_a03 10

# --- step 12: voice pre-check (a04: .env credential check — no host install) ---
run_stage_a04 11

# --- step 13: DDS tuning (CycloneDDS buffers + automatic wired-NIC whitelist) ---
# Deterministically configure the cyclonedds environment shared by host nodes and containers. It is not in the a0N stage scripts;
# it runs only from install.sh or standalone (bash resources/dds-tuning.sh).
run_step 13 dds_tuning bash "${RESOURCE_DIR}/dds-tuning.sh"

# --- step 14: NVIDIA Container Toolkit (after reboot — GPU driver modules loaded) ---
# Installing it before reboot (a01/docker-install) fails the toolkit work because the driver kernel module
# is not yet loaded. So it is split after the step-6 reboot and installed once GPU operation is guaranteed.
# Required for the container (yolo) to use the host GPU (compose nvidia device reservation / `--gpus`).
# SKIP_IF_NO_GPU=1: a GPU-less host-only machine skips normally (driver absence is not treated as an error).
# ASSUME_YES=1: auto-consent to the docker restart (non-interactive flow).
run_step 14 nvidia_container_toolkit \
    env ASSUME_YES=1 SKIP_IF_NO_GPU=1 bash "${SCRIPT_DIR}/resources/nvidia-container-toolkit-install.sh"

# --- step 15: fetch application container images (yolo / voice) ---
# fetch-images.sh downloads the build artifact (docker save tar) from public Google Drive, verifies SHA256, then
# docker loads it (fast reproduction without building). If the image is already local, skip (idempotent). On failure the state
# stays not-DONE so a re-run retries only this step.
# A producing machine that builds/verifies the images directly uses `bash containers/build-all.sh` separately
# (build both images + secret-hygiene scan + import/model-load smoke). Uploading that artifact to the drive lets
# other machines reproduce it via this step. The file ID/SHA256 are pinned in resources/config.sh.
run_step 15 container_fetch bash "${SCRIPT_DIR}/containers/fetch-images.sh"

# --- step 16: static ethernet IP (robot LAN: .1 gripper / .100 robot / .30 host) ---
# After all installs, set the wired NIC to the robot-LAN static IP (nmcli). No gateway/DNS → wifi
# internet stays. Idempotent. No confirm (reversible; the single consent at the start of the run covers it).
# (The unified host workspace — including the container dev bind-mount subdirs (cobot2/yolo_container, voice_container) —
#  is created earlier by the DSR step's dsr-project-install.sh, so no separate dev-workspace step is needed.)
run_step 16 network_static_ip bash "${RESOURCE_DIR}/network-static-ip.sh"

# --- step 17: relocate the corecode tutorials into the user's home (~/corecode) ---
# After all installs, move the repo's corecode/ tutorials to ${HOME}/corecode so they are usable
# independently of the installer checkout location. Idempotent — skips if already relocated or the source
# is gone (and re-run safe via the state file). Runs as the regular user → no sudo needed.
run_step 17 corecode_relocate bash "${RESOURCE_DIR}/corecode-relocate.sh"

# Clean up the resume autostart (no-op if already removed on resume entry — idempotent).
remove_resume_autostart 2>/dev/null || true

state_dump
echo "install: all 17 steps complete — host setup + container images + static network IP + corecode relocation done."
echo "         detailed log: ${LOG_FILE}"
