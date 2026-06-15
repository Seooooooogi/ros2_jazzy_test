#!/usr/bin/env bash
# =============================================================
#  ros2_jazzy_test — ROS2 Jazzy workstation installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/voice-env-check.sh — voice feature pre-check (no host install).
#
# The voice/inference Python packages (langchain / openai / sounddevice, etc.) are installed not on the host but
# only inside the separate (yolo/voice) containers. The host step's role is solely to check the .env credentials
# that the container will mount (app images come from a public Drive tar → docker load, so no registry login is needed).
# No state calls. If OPENAI_API_KEY is missing, prompt for it on the spot and write it to .env
# (does not fail-stop). The credential value is hidden on input + never printed to console/log.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# The .env loader (_load_env/_require_env/_set_env_key/_relocate_example_secret) is in interaction.sh.
# shellcheck source=./interaction.sh
source "${SCRIPT_DIR}/interaction.sh"
config_assert_set

REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_DIR}/.env"
ENV_EXAMPLE="${REPO_DIR}/.env.example"

# 1) ensure .env — create it from the template if missing. Do not stop here: the key is filled in 2) below
#    by the user typing it in (instead of fail-stopping, prompt for it on the spot).
if [[ ! -f "${ENV_FILE}" ]]; then
    if [[ -f "${ENV_EXAMPLE}" ]]; then
        cp "${ENV_EXAMPLE}" "${ENV_FILE}"
        chmod 600 "${ENV_FILE}"
        echo "voice: .env was missing, created it from .env.example → ${ENV_FILE}" >&2
    else
        echo "voice: neither .env nor .env.example exists — prepare a credential template first." >&2
        exit 1
    fi
fi

# 2) obtain OPENAI_API_KEY — pass if already set; if empty, prompt for it on the spot and write it
#    to .env. The input is not shown (read -s) and never printed to console/log.
#    The voice container uses this .env via a runtime mount.
# If a real key was accidentally placed in the tracked file (.env.example), move it to .env and restore the example (secret prevention).
_relocate_example_secret "${ENV_FILE}" "${ENV_EXAMPLE}" OPENAI_API_KEY
# Key presence is judged from the ".env file content", not the "shell environment variable" — the container reads only .env
# (it does not inherit the shell env), so even if exported in the shell, an empty .env kills the container with a missing key.
if grep -qE '^[[:space:]]*OPENAI_API_KEY=.+' "${ENV_FILE}"; then
    echo "voice: OPENAI_API_KEY confirmed (.env — the voice container uses it via mount)." >&2
elif [[ -t 0 ]]; then
    echo "voice: OPENAI_API_KEY is not in .env. If you type it now, it will be saved to ${ENV_FILE}." >&2
    echo "       The input is not shown on screen. Leave it blank and press Enter to skip." >&2
    printf '  OPENAI_API_KEY: ' >&2
    read -rs _openai_key
    echo >&2   # read -s leaves no newline, so add one manually
    if [[ -n "${_openai_key}" ]]; then
        _set_env_key "${ENV_FILE}" OPENAI_API_KEY "${_openai_key}"
        unset _openai_key
        echo "voice: saved OPENAI_API_KEY to ${ENV_FILE} (value not shown)." >&2
    else
        unset _openai_key
        echo "voice: input empty, skipping OPENAI_API_KEY — it must be set in .env before running the voice container." >&2
    fi
else
    echo "voice: warning — OPENAI_API_KEY is empty and this is a non-interactive run, so it cannot be prompted." >&2
    echo "       Set 'OPENAI_API_KEY=...' in ${ENV_FILE} directly, then run the voice container." >&2
fi

echo "voice: success checking voice environment (no host install — the container actually runs it)"
