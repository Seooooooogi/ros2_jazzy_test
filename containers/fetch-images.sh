#!/usr/bin/env bash
# =============================================================
#  ros2_jazzy_test — ROS2 Jazzy workstation installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# Phase 4 application image fetch — instead of building, download a tar from public Google Drive and docker load.
#
# This is the default path of a clean install (install.sh step14). To build/verify the images directly (image-producing
# machine), use containers/build-all.sh. This script only reproduces that artifact (docker save tar).
#
# Behavior:
#   1) skip if the target image is already local (idempotent — re-run/resume safe).
#   2) download the tar via the public drive file ID (handles the large-file virus-scan confirm token).
#   3) verify SHA256 (against the value pinned in config) — blocks corruption/tampering.
#   4) if gz/zip, extract then docker load.
#
# The file ID / SHA256 are pinned in config.sh (a public-link ID is not a secret). Fill in the ID after upload.
# Usage: bash containers/fetch-images.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=resources/config.sh
source "${REPO_ROOT}/resources/config.sh"

# Download working directory (machine-specific artifact — not tracked in the repo).
WORKDIR="${IMAGE_FETCH_DIR:-${STATE_DIR}/images}"
mkdir -p "${WORKDIR}"

# Image definition: "localtag|driveID|sha256|filename". Same defaults as build-all.sh's image coordinates.
IMAGES=(
    "docker.io/${DOCKERHUB_USER:-local}/ros2-jazzy-yolo:${YOLO_TAG:-dev}|${YOLO_IMAGE_GDRIVE_ID:-}|${YOLO_IMAGE_SHA256:-}|ros2-jazzy-yolo-dev.tar"
    "docker.io/${DOCKERHUB_USER:-local}/ros2-jazzy-voice:${VOICE_TAG:-dev}|${VOICE_IMAGE_GDRIVE_ID:-}|${VOICE_IMAGE_SHA256:-}|ros2-jazzy-voice-dev.tar"
)
TOTAL="${#IMAGES[@]}"

# Download a large public Google Drive file. For >100MB the first request returns a virus-scan confirm form (HTML),
# so we extract the confirm/uuid token and make a second request to get the actual binary. Small files come back directly on the first request.
gdrive_download() {
    local id="$1" out="$2"
    local base="https://drive.usercontent.google.com/download"
    local cookie; cookie="$(mktemp)"
    local html; html="$(curl -sL -c "${cookie}" "${base}?id=${id}&export=download")"
    # --no-progress-meter: turns off the progress bar (curl prints it to stderr). orchestrate.sh's run_step sends stderr
    # to the console too, so the old -# progress bar ('###..%') leaked to the console. Unlike -s, errors are still shown.
    if printf '%s' "${html}" | grep -q 'name="confirm"'; then
        local confirm uuid
        confirm="$(printf '%s' "${html}" | grep -o 'name="confirm" value="[^"]*"' | sed -E 's/.*value="([^"]*)".*/\1/')"
        uuid="$(printf '%s' "${html}" | grep -o 'name="uuid" value="[^"]*"' | sed -E 's/.*value="([^"]*)".*/\1/')"
        curl -fL --no-progress-meter --retry 3 --retry-delay 5 -c "${cookie}" -o "${out}" \
            "${base}?id=${id}&export=download&confirm=${confirm}&uuid=${uuid}"
    else
        curl -fL --no-progress-meter --retry 3 --retry-delay 5 -c "${cookie}" -o "${out}" \
            "${base}?id=${id}&export=download"
    fi
    rm -f "${cookie}"
}

n=0
for entry in "${IMAGES[@]}"; do
    n=$((n + 1))
    IFS='|' read -r tag id sha fname <<< "${entry}"
    printf '\n[%d/%d] %s\n' "${n}" "${TOTAL}" "${tag}"

    if docker image inspect "${tag}" >/dev/null 2>&1; then
        echo "  ✓ already present locally — skip"
        continue
    fi
    if [[ -z "${id}" ]]; then
        echo "  ✗ drive file ID unset (config.sh's *_IMAGE_GDRIVE_ID)." >&2
        echo "    Fill in the ID after upload, or run containers/build-all.sh to build directly." >&2
        exit 1
    fi

    tarpath="${WORKDIR}/${fname}"
    echo "  · download → ${tarpath}"
    gdrive_download "${id}" "${tarpath}"

    if [[ -n "${sha}" ]]; then
        echo "  · SHA256 verify"
        echo "${sha}  ${tarpath}" | sha256sum -c - \
            || { echo "  ✗ checksum mismatch — suspected corruption/tampering, aborting" >&2; exit 1; }
    else
        echo "  ! SHA256 unset — skipping integrity verification (pinning in config is recommended)" >&2
    fi

    # Decompression branch. docker load auto-detects gzip, but explicit extraction generalizes both gz/zip.
    case "${tarpath}" in
        *.gz)  echo "  · gunzip"; gunzip -f "${tarpath}"; tarpath="${tarpath%.gz}";;
        *.zip) echo "  · unzip";  unzip -o "${tarpath}" -d "${WORKDIR}"; tarpath="${WORKDIR}/$(basename "${tarpath}" .zip).tar";;
    esac

    echo "  · docker load"
    docker load -i "${tarpath}"
    rm -f "${tarpath}"          # tar not needed after load — reclaim disk (re-run skips since the image exists)
    echo "  ✓ load complete"
done

echo
echo "✅ image fetch complete — ${TOTAL} images. (direct build/verification is containers/build-all.sh)"
