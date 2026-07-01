#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/nvidia-driver-install.sh — NVIDIA GPU driver install (a01 step 2, after the kernel baseline).
#
# Policy:
#   - Default: explicitly pin-install the driver via NVIDIA_DRIVER_VERSION + NVIDIA_DRIVER_FLAVOR
#     (default: nvidia-driver-595 closed). Auto-selection picks a different driver per machine/time,
#     which is non-deterministic and pulled in a half HWE kernel without modules-extra, causing a black
#     screen on reboot → we pin to deterministically reproduce the work machine's verified configuration.
#   - Also install the HWE kernel-module meta (linux-modules-nvidia-...-generic-hwe-24.04) →
#     on a kernel update it automatically pulls the matching nvidia module, staying in sync.
#   - apt-mark hold the driver userspace (blocks major drift from apt upgrade). Do not hold the kernel/module
#     meta — holding it breaks kernel tracking so the module drops out on the next kernel.
#   - If NVIDIA_DRIVER_VERSION is empty, fall back to ubuntu-drivers auto-selection (override, accepting non-determinism).
#   - Pre-reboot verification gate: check the to-be-booted kernel actually has the nvidia kernel module and
#     stop with exit 1 if not — blocking the black-screen brick before reboot.
#   - No reboot here — a01's reboot step handles it after a confirm.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

# Enable apt components — nvidia-modprobe belongs to multiverse, so on installs (server/minimal) where
# multiverse is off it fails with 'unable to locate package nvidia-modprobe'.
# software-properties-common is in main so it is always installable; add-apt-repository is a no-op if already enabled.
# (Reason for placing it in this step: re-guaranteed on every retry/resume — unaffected even if kernel-baseline
# is skipped as DONE.)
sudo apt-get update
sudo apt-get install -y software-properties-common
sudo add-apt-repository -y universe
sudo add-apt-repository -y multiverse

# Build tools + ubuntu-drivers (apt-get install is idempotent on its own).
sudo apt-get update
sudo apt-get install -y build-essential gcc ubuntu-drivers-common dkms nvidia-modprobe

# Resolve the installed nvidia-driver-NNN meta-package name. ubuntu-drivers may pick a -open / -server
# variant, so allow the suffix (e.g. nvidia-driver-595-open).
# The 2nd char of Status-Abbrev = 'i' = currently installed. A held package is 'hi', so looking only for 'ii'
# would miss it (this script holds it itself, so a re-run sees 'hi') → match with '^.i'.
_resolve_driver_pkg() {
    dpkg-query -W -f='${db:Status-Abbrev}|${Package}\n' 'nvidia-driver-*' 2>/dev/null \
        | awk -F'|' '$1 ~ /^.i/ {print $2}' \
        | grep -E '^nvidia-driver-[0-9]+(-open|-server|-server-open)?$' | sort -V | tail -n1 || true
}

# Driver install: skip if already installed (re-run idempotency) / pinned → that version+flavor / otherwise auto fallback.
driver_pkg="$(_resolve_driver_pkg)"
if [[ -n "${driver_pkg}" ]]; then
    echo "nvidia: already installed (${driver_pkg}) — skipping the install step"
elif [[ -n "${NVIDIA_DRIVER_VERSION}" ]]; then
    # Pin install (default path): driver userspace + HWE kernel-module meta together.
    # On a kernel update the module meta automatically pulls the matching nvidia module, staying in sync.
    pin_pkg="nvidia-driver-${NVIDIA_DRIVER_VERSION}${NVIDIA_DRIVER_FLAVOR}"
    module_meta="linux-modules-nvidia-${NVIDIA_DRIVER_VERSION}${NVIDIA_DRIVER_FLAVOR}-${KERNEL_META#linux-}"
    echo "nvidia: pin install ${pin_pkg} (+ kernel-module meta ${module_meta})"
    sudo apt-get install -y "${pin_pkg}" "${module_meta}"
    driver_pkg="$(_resolve_driver_pkg)"
else
    echo "nvidia: NVIDIA_DRIVER_VERSION unset — falling back to ubuntu-drivers auto-selection (non-deterministic)" >&2
    echo "  warning: the fallback path does not install the kernel-module meta (linux-modules-nvidia-...-generic-hwe-24.04)." >&2
    echo "  After the next kernel update, check 'dkms status' / nvidia module loading." >&2
    sudo ubuntu-drivers install
    driver_pkg="$(_resolve_driver_pkg)"
fi

if [[ -z "${driver_pkg}" ]]; then
    echo "nvidia: could not find an installed nvidia-driver-NNN package" >&2
    exit 1
fi

# Hold only the driver userspace so apt upgrade cannot unpin it (skip if already held — idempotent).
# Do not hold the kernel-module meta: holding it breaks kernel-update tracking so the nvidia module drops out on the next kernel.
if apt-mark showhold | grep -qx "${driver_pkg}"; then
    echo "nvidia: ${driver_pkg} already held"
else
    sudo apt-mark hold "${driver_pkg}"
fi

echo "nvidia: installed & held -> ${driver_pkg}"

# --- pre-reboot verification gate ---
# Check the to-be-booted kernel actually has the nvidia kernel module.
# Before reboot, $(uname -r) may still be the old kernel, so we look at the 'to-be-booted kernel' rather than
# the 'running kernel'. If the module is missing, reboot would yield a black screen due to the missing display
# driver, so we stop here (silent brick → loud pre-reboot failure).
# Assumption: GRUB default is the latest installed kernel (Ubuntu default GRUB_DEFAULT=0 + update-grub ordering).
# In an environment where grub-reboot etc. pins a specific older kernel, this check may be inaccurate.
# /lib/modules may have non-version entries like 'kernel' besides version dirs, so pick only the version
# pattern (starting with a digit) and take the latest.
target_kernel="$(find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | grep -E '^[0-9]+\.' | sort -V | tail -n1)"
if find "/lib/modules/${target_kernel}" -name 'nvidia.ko*' 2>/dev/null | grep -q .; then
    echo "nvidia: verification OK — the to-be-booted kernel (${target_kernel}) has the nvidia kernel module."
    echo "nvidia: applying requires a reboot (handled after a confirm in a01's reboot step)."
else
    echo "nvidia: verification failed — the to-be-booted kernel (${target_kernel}) lacks nvidia.ko." >&2
    echo "  Rebooting now could yield a black screen (no display driver), so we stop." >&2
    echo "  Check: 'dkms status' / 'dpkg -l linux-modules-nvidia-*' / /var/log/apt/term.log" >&2
    exit 1
fi
