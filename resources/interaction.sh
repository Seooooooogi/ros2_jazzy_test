#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck shell=bash
# resources/interaction.sh — install UX/secret helpers (.env loader + confirm prompt + resume autostart).
# Source-only library — no `set -euo` here (the calling entry point owns shell options).
#
# Bundles three concerns in one file — all on one axis: "interaction with people/credentials":
#   1) env-load   — safely load/record .env credentials without hardcoding them in scripts (manual parsing, no `source`).
#                   Used by openai-key-setup.sh (run by setup-app.sh during container setup) — _set_env_key/_relocate_example_secret.
#   2) confirm    — explicit consent before irreversible operations (reboot / purge / driver swap).
#   3) resume     — register/remove a one-shot GUI autostart entry so install.sh auto-resumes after the step-6 reboot.
#
# Functions resolve at call time, so only definition order matters, independent of the caller's source order.

# ============================================================================
# 1) env-load — Safe .env loader (load credentials from .env instead of hardcoding them in scripts)
# ============================================================================
# Usage:
#   _load_env "${HOME}/ros2_jazzy_test/.env"
#   _require_env OPENAI_API_KEY
#   # ${OPENAI_API_KEY} is usable afterwards. Never echo / log the value.
#
# Format: KEY=VALUE per line. Ignore blank lines and # comments. No quote support (simple format).
# Security: does not use `source` (blocks a malicious .env file from running shell commands). Manual parsing.

_load_env() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "env-load: file not found: $file" >&2
        return 1
    fi

    # Permission warning: if .env is world-readable, only warn (do not force chmod).
    if [[ "$(stat -c %a "$file" 2>/dev/null)" == *[4-7] ]]; then
        echo "env-load: warning — $file is world-readable. Consider chmod 600." >&2
    fi

    local key value
    while IFS='=' read -r key value; do
        # skip blank lines / comments
        [[ -z "${key// }" || "$key" =~ ^[[:space:]]*# ]] && continue
        # trim leading/trailing whitespace from key
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        # validate variable name (security: block arbitrary variable injection)
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        # export the value (no quote handling — convention is no quotes in .env)
        export "${key}=${value}"
    done < "$file"
}

# Public: error if a required variable is empty. Never print the value itself.
_require_env() {
    local var="$1"
    if [[ -z "${!var:-}" ]]; then
        echo "env: required variable '$var' is empty (set in .env or environment)" >&2
        return 1
    fi
}

# Public: set KEY to VALUE in .env (replace if present, append if absent). Never print the value.
# A commented-out '# KEY=' line is also replaced with an active 'KEY=VALUE'.
# Does not pass the value as an argument to external commands like sed/awk (pure bash) — preventing both
# special-character corruption of the API key and exposure via the `ps` process list. The temp file is created
# next to .env (same fs) with mode 600 and swapped via atomic rename, so the secret does not leak through /tmp.
_set_env_key() {
    local file="$1" key="$2" value="$3"
    # validate variable name — block arbitrary key injection (same policy as _load_env). Never print the value.
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "env-load: invalid key name" >&2; return 1; }
    local tmp line found=0
    tmp="$(mktemp "${file}.XXXXXX")" || return 1
    chmod 600 "$tmp"
    if [[ -f "$file" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^[[:space:]]*#?[[:space:]]*"${key}"= ]]; then
                printf '%s=%s\n' "$key" "$value" >> "$tmp"
                found=1
            else
                printf '%s\n' "$line" >> "$tmp"
            fi
        done < "$file"
    fi
    [[ "$found" -eq 0 ]] && printf '%s=%s\n' "$key" "$value" >> "$tmp"
    mv "$tmp" "$file"
    chmod 600 "$file"
}

# Public: move a real KEY value accidentally placed in the tracked file (.env.example) to .env and restore
# the example to a placeholder. .env.example is git-tracked, so a leftover real value leaks the secret.
# Never print the value to screen/log. Idempotent — does nothing if the example has no value.
# Args: <env_file> <env_example> <key>
_relocate_example_secret() {
    local env_file="$1" example="$2" key="$3"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "env-load: invalid key name" >&2; return 1; }
    [[ -f "$example" ]] || return 0
    # Find the KEY line in the example that has a value (content after '=') (regardless of comment state). Value not printed.
    local line val
    line="$(grep -E "^[[:space:]]*#?[[:space:]]*${key}=.+" "$example" 2>/dev/null | head -1)" || true
    [[ -z "$line" ]] && return 0
    val="${line#*=}"
    [[ "$val" =~ ^[[:space:]]*$ ]] && return 0   # ignore empty/whitespace placeholder
    echo "env-load: warning — the tracked file ${example} contains a real value for ${key} (secret-leak risk)." >&2
    echo "          Moving it to ${env_file} and restoring ${example} to a placeholder (value not shown)." >&2
    # Ensure .env exists, then move the key (_set_env_key does not print the value).
    [[ -f "$env_file" ]] || { : > "$env_file"; chmod 600 "$env_file"; }
    _set_env_key "$env_file" "$key" "$val"
    # Restore the matching example line to an empty placeholder ('# KEY=') to remove the value.
    local tmp l
    tmp="$(mktemp "${example}.XXXXXX")" || return 1
    chmod 600 "$tmp"
    while IFS= read -r l || [[ -n "$l" ]]; do
        if [[ "$l" =~ ^[[:space:]]*#?[[:space:]]*${key}= ]]; then
            printf '# %s=\n' "$key" >> "$tmp"
        else
            printf '%s\n' "$l" >> "$tmp"
        fi
    done < "$example"
    mv "$tmp" "$example"
    echo "env-load: ${key} moved — rotating the exposed key is recommended." >&2
}

# ============================================================================
# 2) confirm — explicit consent before irreversible (state-changing) operations
# ============================================================================
# (irreversible operations like sudo reboot / apt purge / driver swap require explicit user consent).
#
# Usage:
#   confirm_or_abort "Reboot now? Unsaved work will be lost."
#
# Default: N. Only [yY] proceeds. On a non-interactive shell (no TTY), abort safely.

confirm_or_abort() {
    local msg="$1"
    local reply=""

    # On a non-interactive shell (CI / cron / systemd), default N — never proceed without a user decision.
    if [[ ! -t 0 ]]; then
        echo "confirm: non-interactive shell, aborting." >&2
        echo "        msg: $msg" >&2
        exit 1
    fi

    read -p "${msg} (y/N): " -n 1 -r reply
    echo
    if [[ ! "$reply" =~ ^[yY]$ ]]; then
        echo "Aborted by user."
        exit 0
    fi
}

# Public: when you do not want to ask the same message again — auto-consent if the env var ASSUME_YES=1.
# A channel for a CI / automation wrapper to explicitly express consent.
confirm_or_abort_assumable() {
    local msg="$1"
    if [[ "${ASSUME_YES:-0}" == "1" ]]; then
        echo "${msg} (auto-confirmed via ASSUME_YES=1)"
        return 0
    fi
    confirm_or_abort "$msg"
}

# ============================================================================
# 3) resume — auto-resume the install across the step-6 reboot
# ============================================================================
# Register/remove a one-shot GUI autostart entry so install.sh continues automatically after its reboot.
# (OPENAI_API_KEY is no longer pre-collected here — it is install.sh's final step, openai-key-setup.sh.)
#
# Mechanism: GNOME autostart (.desktop) opens a terminal on login to run install-resume-launcher.sh
# → relaunches install.sh. When install.sh re-enters on resume, it immediately removes
# the autostart (one-shot) so it does not re-fire on every login.

RESUME_AUTOSTART_DIR="${HOME}/.config/autostart"
RESUME_AUTOSTART_FILE="${RESUME_AUTOSTART_DIR}/ros2-jazzy-install-resume.desktop"

# Register auto-resume after reboot: launch install-resume-launcher.sh from a terminal on login.
register_resume_autostart() {
    local repo="$1"
    local launcher="${repo}/resources/install-resume-launcher.sh"
    local exec_line=""
    if command -v gnome-terminal >/dev/null; then
        exec_line="gnome-terminal -- bash \"${launcher}\""
    elif command -v x-terminal-emulator >/dev/null; then
        exec_line="x-terminal-emulator -e bash \"${launcher}\""
    else
        echo "[install] no terminal emulator — auto-resume not possible." >&2
        echo "             after reboot, run 'bash install.sh' manually." >&2
        return 0
    fi
    mkdir -p "${RESUME_AUTOSTART_DIR}"
    cat > "${RESUME_AUTOSTART_FILE}" <<EOF
[Desktop Entry]
Type=Application
Name=ros2_jazzy_test install resume
Comment=Auto-resume install.sh after a clean-install reboot (one-shot)
Exec=${exec_line}
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
    echo "[install] registered auto-resume after reboot: ${RESUME_AUTOSTART_FILE}" >&2
}

# Remove the autostart entry (idempotent) — called on resume entry (to guarantee one-shot) and on completion.
remove_resume_autostart() {
    if [[ -f "${RESUME_AUTOSTART_FILE}" ]]; then
        rm -f "${RESUME_AUTOSTART_FILE}"
        echo "[install] removed auto-resume entry: ${RESUME_AUTOSTART_FILE}" >&2
    fi
    return 0
}
