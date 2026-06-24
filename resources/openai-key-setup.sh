#!/usr/bin/env bash
# =============================================================
#  ros2_jazzy_test — ROS2 Jazzy workstation installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/openai-key-setup.sh — OPENAI_API_KEY setup (run by setup-app.sh during container setup; no host install).
#
# The voice/inference Python packages live only inside the application containers, which read OPENAI_API_KEY
# from the repo-root .env via a runtime mount. This step's sole job is to put that key into .env. It NEVER
# fail-stops: if the key is missing it prompts once (hidden input), and an empty answer is fine — the user can
# edit .env directly later. The credential value is hidden on input + never printed to console/log.
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

# 1) ensure .env — create it from the template if missing. Do not stop here: the key is filled in 2) below.
if [[ ! -f "${ENV_FILE}" ]]; then
    if [[ -f "${ENV_EXAMPLE}" ]]; then
        cp "${ENV_EXAMPLE}" "${ENV_FILE}"
        chmod 600 "${ENV_FILE}"
        echo "openai-key: .env was missing, created it from .env.example → ${ENV_FILE}" >&2
    else
        echo "openai-key: neither .env nor .env.example exists — prepare a credential template first." >&2
        exit 1
    fi
fi

# 2) obtain OPENAI_API_KEY — pass if already set; if empty, prompt for it on the spot and write it to .env.
#    The input is not shown (read -s) and never printed to console/log. The application container reads this
#    .env via a runtime mount.
# If a real key was accidentally placed in the tracked file (.env.example), move it to .env and restore the example (secret prevention).
_relocate_example_secret "${ENV_FILE}" "${ENV_EXAMPLE}" OPENAI_API_KEY
# Key presence is judged from the ".env file content", not the "shell environment variable" — the container reads only .env
# (it does not inherit the shell env), so even if exported in the shell, an empty .env kills the container with a missing key.
if grep -qE '^[[:space:]]*OPENAI_API_KEY=.+' "${ENV_FILE}"; then
    echo "openai-key: OPENAI_API_KEY confirmed (.env — the application container uses it via mount)." >&2
elif [[ -t 0 ]]; then
    echo "openai-key: OPENAI_API_KEY is not in .env. If you type it now, it will be saved to ${ENV_FILE}." >&2
    echo "           The input is not shown on screen. Leave it blank and press Enter to skip (you can edit .env later)." >&2
    printf '  OPENAI_API_KEY: ' >&2
    read -rs _openai_key
    echo >&2   # read -s leaves no newline, so add one manually
    if [[ -n "${_openai_key}" ]]; then
        _set_env_key "${ENV_FILE}" OPENAI_API_KEY "${_openai_key}"
        unset _openai_key
        echo "openai-key: saved OPENAI_API_KEY to ${ENV_FILE} (value not shown)." >&2
    else
        unset _openai_key
        echo "openai-key: input empty, skipping — set 'OPENAI_API_KEY=...' in ${ENV_FILE} before running the application container." >&2
    fi
else
    echo "openai-key: warning — OPENAI_API_KEY is empty and this is a non-interactive run, so it cannot be prompted." >&2
    echo "           Set 'OPENAI_API_KEY=...' in ${ENV_FILE} directly before running the application container." >&2
fi

echo "openai-key: done (key lives in ${ENV_FILE}; the application container reads it via mount)."
