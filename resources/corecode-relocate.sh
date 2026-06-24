#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# resources/corecode-relocate.sh — move the repo's corecode/ tutorials into the user's home (install.sh step 17).
#
# corecode/ holds the standalone tutorials (Calibration_Tutorial / VoiceProcessing). After the install, relocate
# them to ${HOME}/corecode so they are usable independently of the installer checkout location (e.g. running the
# installer from removable media or a temp clone). Runs as the regular install user, so ${HOME} is user-writable
# and no sudo is needed.
#
# Idempotent: if the destination already exists, or the source is gone (already relocated), it is a no-op. The
# destination is never overwritten — if BOTH source and destination exist, the move is skipped and a warning is
# logged for manual review (so a re-cloned repo does not clobber an already-relocated, possibly-edited copy).
# This script is a pure install body — the state framing (run_step) is owned by the caller (install.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="${REPO_DIR}/corecode"
DEST="${HOME}/corecode"

if [[ -d "${DEST}" ]]; then
    if [[ -d "${SRC}" ]]; then
        echo "corecode: ${DEST} already exists — leaving ${SRC} in place to avoid overwrite (skip)" >&2
    else
        echo "corecode: already relocated to ${DEST} (skip)"
    fi
    exit 0
fi

if [[ ! -d "${SRC}" ]]; then
    echo "corecode: source ${SRC} not found — nothing to relocate (skip)"
    exit 0
fi

mv "${SRC}" "${DEST}"
echo "corecode: moved ${SRC} -> ${DEST}"
