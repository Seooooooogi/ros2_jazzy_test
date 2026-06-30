#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# setup-app.sh — application layer setup, separate from the base host install (install.sh).
#
# install.sh sets up only the base host environment (OS / NVIDIA / Docker / ROS2 + reboot + VS Code +
# DDS tuning + static IP + corecode). This script sets up the cobot2 APPLICATION on top:
#
#   workspace : doosan-robot2 driver clone + DSR deps + emulator → verify cobot2 source → RealSense → colcon build.
#   containers: nvidia-container-toolkit → application container images (built from source by default — students
#               develop on the cobot2 template; --fetch pulls prebuilt instead) → OPENAI_API_KEY into .env.
#
# The cobot2 application source is NOT shipped by this repo. The user places it at ${DSR_WORKSPACE}/src/cobot2
# (see obtain_cobot2 below — isolated so it can later be swapped for a git clone / tarball fetch). Without it,
# the workspace step fails loud rather than building a partial workspace that only breaks at runtime.
#
# Run after install.sh (and its reboot) completes. Supersedes the old reinstall-workspace.sh.
#
# Console shows only the [n/total] step banner + a liveness heartbeat; each step's detailed output
# (apt / colcon / docker) goes to the repo-root install_log. --verbose (or VERBOSE=1) also streams it
# to the console. sudo password prompts use /dev/tty, so they stay visible even when output is routed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="${SCRIPT_DIR}/resources"

# shellcheck source=resources/config.sh
source "${RESOURCE_DIR}/config.sh"
# shellcheck source=resources/interaction.sh
source "${RESOURCE_DIR}/interaction.sh"   # sudo_prime
config_assert_set

# Per-step detail is routed here (same install_log as install.sh); console stays clean unless --verbose.
LOG="${LOG_FILE}"
mkdir -p "$(dirname "${LOG}")"
VERBOSE="${VERBOSE:-0}"

DO_WORKSPACE=1
DO_CONTAINERS=1
RESET=0
BUILD=1   # default: build container images from source (the course has students modify the cobot2 template). --fetch selects prebuilt.
ASSUME_YES=0

usage() {
    cat <<EOF
setup-app.sh — set up the cobot2 application (workspace + containers) on top of the base install.sh.

  bash setup-app.sh                 workspace (driver + cobot2 + RealSense + colcon) + containers (toolkit + build images from source + OPENAI key)
  bash setup-app.sh --workspace-only   only the colcon workspace
  bash setup-app.sh --containers-only  only the container layer (toolkit + images + OPENAI key)
  bash setup-app.sh --reset         wipe the doosan-robot2 clone + build/install/log first, then rebuild
                                    (cobot2 source is NOT touched). Asks to confirm unless --yes.
  bash setup-app.sh --fetch         containers: pull prebuilt images instead of building from source
                                    (default builds from source — students develop on the cobot2 template).
  bash setup-app.sh --verbose       also stream each step's detailed output to the console (default: only install_log).
  bash setup-app.sh -y, --yes       skip the --reset confirmation (non-interactive).
  bash setup-app.sh -h, --help      this help.

The cobot2 application source is NOT shipped by this repo — place it at ${DSR_WORKSPACE}/src/cobot2 before running.
EOF
}

# Project copyright banner — printed to the console at the start of every actual run (same as install.sh).
print_copyright() {
    cat <<'EOF'
============================================================
 Cobot2 Jazzy Installer
 Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
============================================================
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose)      VERBOSE=1 ;;
        --workspace-only)  DO_CONTAINERS=0 ;;
        --containers-only) DO_WORKSPACE=0 ;;
        --reset)           RESET=1 ;;
        --fetch)           BUILD=0 ;;   # pull prebuilt images instead of the default source build
        --build)           BUILD=1 ;;   # accepted for back-compat; building from source is now the default
        -y|--yes)          ASSUME_YES=1 ;;
        -h|--help)         usage; exit 0 ;;
        *) echo "[setup-app] unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if [[ ${DO_WORKSPACE} -eq 0 && ${DO_CONTAINERS} -eq 0 ]]; then
    echo "[setup-app] --workspace-only and --containers-only are mutually exclusive." >&2
    exit 2
fi

# Copyright banner for an actual run (the --help subcommand above has already exited).
print_copyright

# progress denominator (purely for the [n/total] display).
TOTAL=0
[[ ${DO_WORKSPACE} -eq 1 ]] && TOTAL=$(( TOTAL + 5 ))   # cobot2-verify + dsr + rs-sdk + rs-ros + colcon
[[ ${DO_CONTAINERS} -eq 1 ]] && TOTAL=$(( TOTAL + 4 ))  # toolkit + images + domain-id + openai-key
STEP_N=0
# Per-step banner — same framed [n/total] format as install.sh (orchestrate.sh step_begin).
step() {
    STEP_N=$(( STEP_N + 1 ))
    echo
    echo "============================================================"
    echo "[${STEP_N}/${TOTAL}] ${*}"
    echo "============================================================"
}

# Liveness heartbeat while a routed step runs (so the clean console does not look stuck). First draw is
# delayed 2s so a sudo password prompt at step start (sudo uses /dev/tty) is not overwritten.
_hb() {
    local name="$1" start="$SECONDS" e
    while :; do
        sleep 2
        e=$(( SECONDS - start ))
        printf '\r  ⋯ %s (%02d:%02d)\033[K' "$name" $(( e / 60 )) $(( e % 60 )) >&2
    done
}

# run <label> <cmd...> — print the step banner, then run the command with its detailed output routed to
# the log (console keeps just the banner + heartbeat). VERBOSE=1 / --verbose also tees it to the console.
# On failure: one-line [FAIL] + the log path, then exit. (Interactive / quick steps call step() directly.)
run() {
    local label="$1"; shift
    step "${label}"
    { echo; echo "===== setup-app: ${label} — $(date '+%F %T') ====="; } >>"${LOG}"
    local rc=0 hb=""
    if [[ "${VERBOSE}" == 1 ]]; then
        set +e; "$@" 2>&1 | tee -a "${LOG}"; rc=${PIPESTATUS[0]}; set -e
    else
        if [[ -t 2 ]]; then _hb "${label}" & hb=$!; fi
        "$@" >>"${LOG}" 2>&1 || rc=$?
        if [[ -n "${hb}" ]]; then
            kill "${hb}" 2>/dev/null || true
            wait "${hb}" 2>/dev/null || true
            printf '\r\033[K' >&2
        fi
    fi
    if [[ ${rc} -ne 0 ]]; then
        echo "[setup-app] FAILED: ${label} (rc=${rc}) — see ${LOG}" >&2
        exit "${rc}"
    fi
}

# obtain_cobot2 — get the cobot2 application source into ${DSR_WORKSPACE}/src/cobot2.
# CURRENT POLICY: manual placement by the user — verify presence, fail loud if absent.
# This is the single isolated seam for the source-acquisition policy: to switch to a git clone or a
# tarball fetch later, replace only this function body (e.g. `git clone <url> "${cobot2}"`).
obtain_cobot2() {
    local cobot2="${DSR_WORKSPACE}/src/cobot2"
    if [[ -d "${cobot2}" ]] && find "${cobot2}" -name package.xml -print -quit | grep -q .; then
        echo "setup-app: cobot2 source found at ${cobot2}"
        return 0
    fi
    echo "setup-app: cobot2 application source not found at ${cobot2}" >&2
    echo "           This repo no longer ships cobot2 — place the source there, then re-run:" >&2
    echo "             mkdir -p ${DSR_WORKSPACE}/src && cp -a <cobot2-source> ${cobot2}" >&2
    exit 1
}

do_reset() {
    # Destructive but regenerable (re-clone + rebuild). cobot2 (user-placed) is preserved.
    if [[ ${ASSUME_YES} -ne 1 ]]; then
        if [[ -t 0 ]]; then
            read -r -p "[setup-app] --reset will rm -rf ${DSR_WORKSPACE}/src/doosan-robot2 and ${DSR_WORKSPACE}/{build,install,log} (cobot2 kept). Continue? [y/N] " reply
            [[ "${reply}" =~ ^[Yy]$ ]] || { echo "[setup-app] aborted."; exit 1; }
        else
            echo "[setup-app] --reset needs confirmation but no TTY — re-run with --yes." >&2
            exit 1
        fi
    fi
    echo "[setup-app] reset: wiping doosan-robot2 clone + build/install/log (cobot2 kept)"
    rm -rf "${DSR_WORKSPACE}/src/doosan-robot2" \
           "${DSR_WORKSPACE}/build" "${DSR_WORKSPACE}/install" "${DSR_WORKSPACE}/log"
}

do_workspace() {
    step "cobot2 source (verify)"; obtain_cobot2   # quick verify — stays on the console
    run "doosan-robot2 driver + DSR deps" bash "${RESOURCE_DIR}/dsr-project-install.sh"
    run "RealSense SDK"                   bash "${RESOURCE_DIR}/realsense-install.sh" sdk
    run "RealSense ROS2 wrapper"          bash "${RESOURCE_DIR}/realsense-install.sh" ros
    run "colcon build"                    bash "${RESOURCE_DIR}/colcon-build.sh"
}

do_containers() {
    run "NVIDIA Container Toolkit" env ASSUME_YES=1 SKIP_IF_NO_GPU=1 bash "${RESOURCE_DIR}/nvidia-container-toolkit-install.sh"
    if [[ ${BUILD} -eq 1 ]]; then
        run "build container images (from source)" bash "${SCRIPT_DIR}/containers/build-all.sh"
    else
        run "fetch container images (prebuilt)" bash "${SCRIPT_DIR}/containers/fetch-images.sh"
    fi
    # ROS_DOMAIN_ID → persisted file (config.sh reads it as the default; the containers receive the same
    # value via compose, and new host shells pick it up from the ~/.bashrc managed block planted by
    # dds-tuning). INTERACTIVE prompt → stays on the console. Enter keeps the current value (default 42).
    step "ROS_DOMAIN_ID (DDS domain shared by host and containers)"; prompt_domain_id
    # OPENAI_API_KEY → repo-root .env (the voice container mounts it). INTERACTIVE prompt → stays on the
    # console (not routed to the log). Empty = skip (editable in .env later); idempotent if already set.
    step "OPENAI_API_KEY (.env for the voice container)"; bash "${RESOURCE_DIR}/openai-key-setup.sh"
}

echo "[setup-app] workspace=${DSR_WORKSPACE} | workspace:$([[ ${DO_WORKSPACE} -eq 1 ]] && echo on || echo off) containers:$([[ ${DO_CONTAINERS} -eq 1 ]] && echo on || echo off)$([[ ${RESET} -eq 1 ]] && echo ' | reset')$([[ ${DO_CONTAINERS} -eq 1 ]] && { [[ ${BUILD} -eq 1 ]] && echo ' | images:build(source)' || echo ' | images:fetch(prebuilt)'; })"

[[ ${RESET} -eq 1 ]] && do_reset

# Every step below runs sudo (apt / docker). Collect the password ONCE here, before any step banner +
# heartbeat — otherwise the first routed step's sudo prompt is hidden behind the heartbeat and the run
# looks like it proceeds before the password is fully typed. Keepalive keeps it warm through colcon build.
sudo_prime setup-app

[[ ${DO_WORKSPACE} -eq 1 ]] && do_workspace
[[ ${DO_CONTAINERS} -eq 1 ]] && do_containers

echo
echo "[setup-app] done."
[[ ${DO_WORKSPACE} -eq 1 ]] && echo "  workspace: source ${DSR_WORKSPACE}/install/setup.bash"
[[ ${DO_CONTAINERS} -eq 1 ]] && echo "  containers: docker images | run via containers/docker-compose.yml"
echo "  detailed log: ${LOG}"
