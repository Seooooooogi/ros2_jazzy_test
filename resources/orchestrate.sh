#!/usr/bin/env bash
# =============================================================
#  ros2_jazzy_test — ROS2 Jazzy workstation installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck shell=bash
# resources/orchestrate.sh — install step engine (state tracking + run wrapper + step definitions, single source).
# Source-only library — no `set -euo` here (the calling entry point owns shell options).
#
# Bundles three concerns in one file — always sourced together, and you must read all three to follow one step:
#   1) state   — idempotently records step progress (DONE/FAIL/SKIPPED/RUNNING) in the state file (resume + [n/total]).
#   2) run_step — central run wrapper bundling skip decision + begin/end + log separation + heartbeat.
#   3) steps   — step definitions called by the full install.sh sequence (stage functions + denominator constants).
#
# Requires config.sh to be sourced first (STATE_FILE / LOG_FILE / STATE_DIR / TOTAL_STEPS). The caller
# sets RESOURCE_DIR and STEPS_TOTAL. Functions resolve at call time, so source order does not matter.

# ============================================================================
# 1) state — step progress tracking (resumable re-run + [n/total] progress)
# ============================================================================
# State file format (key=value — idempotent state recording via grep/sed-based in-place update):
#   step_<name>=DONE|FAIL|SKIPPED|RUNNING
#
# Usage (from installer step):
#   step_should_skip a01_prerequirements && return 0
#   step_begin 1 6 a01_prerequirements
#   ... do work ...
#   step_end_ok       # or step_end_fail on failure
#
# Idempotent: marking the same step RUNNING -> DONE multiple times keeps a single line in the state file.
# Dependencies: STATE_FILE from config.sh must be defined.

# Internal state: the currently running step name (for pairing step_begin -> step_end_*).
__current_step=""

# Internal: create the state file if it does not exist.
_state_ensure_file() {
    mkdir -p "$(dirname "$STATE_FILE")"
    [[ -f "$STATE_FILE" ]] || : > "$STATE_FILE"
}

# Internal: set the step_<name> line in the state file to status (append if absent, replace if present).
_state_set() {
    local name="$1" status="$2" key
    _state_ensure_file
    key="step_${name}"
    if grep -qE "^${key}=" "$STATE_FILE"; then
        sed -i "s|^${key}=.*|${key}=${status}|" "$STATE_FILE"
    else
        echo "${key}=${status}" >> "$STATE_FILE"
    fi
}

# Public: is this step already marked DONE? return 0 = safe to skip.
step_should_skip() {
    local name="$1"
    _state_ensure_file
    grep -qE "^step_${name}=DONE$" "$STATE_FILE"
}

# Public: begin a step. Print progress + header and record RUNNING in state.
# Args: <n> <total> <name>
step_begin() {
    local n="$1" total="$2" name="$3"
    __current_step="$name"
    _state_ensure_file
    echo
    echo "============================================================"
    echo "[${n}/${total}] step: ${name}"
    echo "============================================================"
    _state_set "$name" RUNNING
}

# Public: finalize the current step as DONE.
step_end_ok() {
    if [[ -z "$__current_step" ]]; then
        echo "state: step_end_ok called without step_begin" >&2
        return 1
    fi
    _state_set "$__current_step" DONE
    echo "[OK]  step ${__current_step} = DONE"
    __current_step=""
}

# Public: finalize the current step as FAIL.
step_end_fail() {
    if [[ -z "$__current_step" ]]; then
        echo "state: step_end_fail called without step_begin" >&2
        return 1
    fi
    _state_set "$__current_step" FAIL
    echo "[FAIL] step ${__current_step} = FAIL" >&2
    __current_step=""
}

# Public: finalize the current step as SKIPPED (on conditional skip).
step_end_skip() {
    if [[ -z "$__current_step" ]]; then
        return 1
    fi
    _state_set "$__current_step" SKIPPED
    echo "[SKIP] step ${__current_step} = SKIPPED"
    __current_step=""
}

# Public: print all step states (for debugging / verification).
state_dump() {
    _state_ensure_file
    echo "--- state file: $STATE_FILE ---"
    cat "$STATE_FILE"
    echo "-------------------------------"
}

# ============================================================================
# 2) run_step — centralized step run wrapper (orchestration policy)
# ============================================================================
# Depends on the state section above (step_should_skip / step_begin / step_end_*) and config.sh (TOTAL_STEPS).
#
# The progress denominator (total) reads STEPS_TOTAL, set by the caller, at call time.
# install.sh sets STEPS_TOTAL (total step count, install_steps_total).
# Falls back to TOTAL_STEPS from config.sh when unset.
#
# State marking/lookup is owned by the state section above; this section only bundles the skip decision + begin/end calls.
#
# Output policy (non-verbose, default): the step command's (`"$@"`) stdout AND stderr both go to LOG_FILE
# from config.sh only — the console is kept clean (just the progress banner from step_begin/step_end_* + a
# liveness heartbeat). Step warnings/errors are NOT shown on the console; they live in the log. A failure is
# still never silent: step_end_fail prints a one-line [FAIL] + the log path. (VERBOSE=1: stdout+stderr are
# teed to both console and log.) See the routing comment inside run_step for the fd mechanics.
#
# On failure it records FAIL via step_end_fail then exits directly with exit 1 — on this path
# the ERR trap installed by the caller does not fire (exit is not a trap target). So failure reporting
# has step_end_fail's FAIL record as the single source of truth, and the ERR trap catches only command failures outside run_step.

# A heartbeat that updates elapsed time in-place (\r) so the console does not look "stuck" during a step.
# Shown only when non-verbose (stdout goes to the log) + interactive (tty). In verbose mode the step's
# actual output (colcon n/total, apt %) flows to the console, so no heartbeat is shown.
# Delay the first draw by 2 seconds: so a short step / the sudo password prompt early in a step does not
# overlap the heartbeat line — sudo usually asks right after a step starts and finishes within it.
_step_heartbeat() {
    local name="$1" start="$SECONDS" e
    while :; do
        sleep 2
        e=$(( SECONDS - start ))
        printf '\r  ⋯ %s running (%02d:%02d elapsed)\033[K' "$name" $(( e / 60 )) $(( e % 60 )) >&2
    done
}

# run_step [--interactive] <n> <name> <cmd...> — skip if DONE, otherwise begin → run → ok/fail.
# --interactive: when a step reads user input from stdin (e.g. typing an API key directly), turn off the
#   heartbeat. Prevents the heartbeat's \r update from overwriting the input prompt and garbling input.
run_step() {
    local interactive=0
    if [[ "${1:-}" == --interactive ]]; then interactive=1; shift; fi
    local n="$1" name="$2"
    shift 2
    if [[ $# -eq 0 ]]; then
        echo "run-step: no command to run for '${name}' (run_step <n> <name> <cmd...>)." >&2
        exit 2
    fi
    local total="${STEPS_TOTAL:-${TOTAL_STEPS:?run-step: STEPS_TOTAL/TOTAL_STEPS not set}}"
    if step_should_skip "${name}"; then
        echo "[${n}/${total}] skip: ${name} (already DONE)"
        return 0
    fi
    # Append a step-separator banner to the detailed install log (LOG_FILE from config.sh). In an environment where
    # LOG_FILE is undefined (old source order), fall back via STATE_DIR so set -u does not kill it.
    local log="${LOG_FILE:-${STATE_DIR:?run-step: STATE_DIR not set}/install.log}"
    mkdir -p "$(dirname "$log")"
    { echo; echo "===== [${n}/${total}] ${name} — $(date '+%F %T') ====="; } >>"$log"

    step_begin "${n}" "${total}" "${name}"

    # Output routing:
    #   default (non-verbose): the command's stdout AND stderr both go to the log only — the console is kept
    #     clean (only the [n/total] banner + a liveness heartbeat). Step warnings/errors are NOT printed to the
    #     console; they live in the log. A failure is still never silent: step_end_fail prints a one-line
    #     [FAIL] + the log path below.
    #   VERBOSE=1: stdout+stderr are teed to both console and log in real time (colcon [n/total], apt %).
    #
    # The verbose tee is an async process-sub that may still be flushing after the command ends; if left open the
    # [OK]/[FAIL] banner could interleave with the command's last line. So we open tee on a dedicated fd via exec,
    # then close it (EOF) and wait for the drain before the banner, making order deterministic. It is a redirect +
    # process-sub, not a pipeline, so pipefail does not apply; the exit code is taken from "$@" into rc
    # (`|| rc=$?` so set -e does not fire). The sudo prompt goes to /dev/tty either way, so it is not swallowed.
    local rc=0 teepid="" tfd=-1 hbpid=""
    if [[ "${VERBOSE:-0}" == 1 ]]; then
        exec {tfd}> >(tee -a "$log" >&2); teepid=$!
        "$@" >&"$tfd" 2>&1 || rc=$?
        exec {tfd}>&-
        wait "$teepid" 2>/dev/null || true
    else
        if [[ -t 2 && "$interactive" -eq 0 ]]; then
            # No per-step log hint here — the heartbeat shows liveness, and the log path is surfaced only
            # on failure (step_end_fail below) or once at the very end of install.sh. Keeps the console clean.
            _step_heartbeat "${name}" & hbpid=$!
        fi
        "$@" >>"$log" 2>&1 || rc=$?
        if [[ -n "$hbpid" ]]; then
            kill "$hbpid" 2>/dev/null || true
            wait "$hbpid" 2>/dev/null || true
            printf '\r\033[K' >&2   # clear leftover heartbeat line
        fi
    fi

    if [[ $rc -eq 0 ]]; then
        step_end_ok
    else
        step_end_fail
        echo "  ↳ detailed log: ${log}" >&2
        exit 1
    fi
}

# ============================================================================
# 3) steps — install step definitions (called from the full install.sh sequence)
# ============================================================================
# Prerequisite: the state/run_step sections above. The caller sets RESOURCE_DIR.
#
# Numbering rule: each stage function takes an offset and computes the run_step number = offset + local-k.
#   install.sh: run_stage_a01 0 → (reboot=step6, inline in install.sh) → run_stage_a03 6
#               → steps 8-10 (dds / network / corecode, install-only, inline in install.sh).
# The application layer (DSR driver + RealSense + cobot2 colcon build + containers) is no longer part of
# install.sh — it lives in setup-app.sh (run after the base install).
# The offset argument is kept for future partial-run/reordering flexibility — currently the only caller is install.sh.
# The state key (name) is independent of offset/number — no effect on resume compatibility (same name → same skip).
#
# reboot (step6) is not placed in this section: install.sh's reboot wrapper owns the messaging and the
# exit-vs-continue (it terminates the process), which differs from run_step's generic step framing.
# install.sh owns reboot inline.

# Per-stage step count (excluding reboot). When adding a step, updating only here makes
# the overall denominator in install_steps_total() follow.
STAGE_A01_COUNT=5
STAGE_A03_COUNT=1
INSTALL_EXTRA_COUNT=3   # install-only: dds(8) / network(9) / corecode(10)

# install.sh overall denominator: a01 5 + reboot 1 + a03 1 + extra 3 = 10.
install_steps_total() {
    echo $(( STAGE_A01_COUNT + 1 + STAGE_A03_COUNT + INSTALL_EXTRA_COUNT ))
}

# a01: kernel baseline → NVIDIA → Docker → ROS2 desktop → ROS2 extras (reboot is inline in the caller).
# ros2-packages.sh runs the desktop/extras subcommands as separate steps in separate processes.
run_stage_a01() {
    local off="$1"
    run_step $((off + 1)) a01_kernel_baseline bash "${RESOURCE_DIR}/kernel-baseline.sh"
    run_step $((off + 2)) a01_nvidia_driver   bash "${RESOURCE_DIR}/nvidia-driver-install.sh"
    run_step $((off + 3)) a01_docker          bash "${RESOURCE_DIR}/docker-install.sh"
    run_step $((off + 4)) a01_ros2_desktop    bash "${RESOURCE_DIR}/ros2-packages.sh" desktop
    run_step $((off + 5)) a01_ros2_extras     bash "${RESOURCE_DIR}/ros2-packages.sh" extras
}

# a03: VS Code.
# (The DSR driver + RealSense + colcon build, formerly run_stage_a02, moved to setup-app.sh.)
run_stage_a03() {
    local off="$1"
    run_step $((off + 1)) a03_vscode bash "${RESOURCE_DIR}/vscode-install.sh"
}
