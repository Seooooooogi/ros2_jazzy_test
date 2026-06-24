#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/kernel-baseline.sh — guarantee the HWE kernel baseline (a01 step 1, before nvidia).
#
# The nvidia driver and RealSense (librealsense2-dkms) are both kernel-coupled modules.
# If only the kernel image is installed and modules-extra (which carries wifi / some USB input drivers) is missing,
# it boots but becomes a half kernel that loses wifi/USB keyboard. Also DKMS modules need the kernel headers
# to build. Explicitly install the HWE meta + headers meta so that image + headers + modules-extra are
# always guaranteed together and automatically tracked through later kernel updates.
# Pure install body — no state calls (the orchestrator owns the step framing).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

# 1) HWE kernel meta + headers meta. --install-recommends also pulls in modules-extra
#    (a missing recommends, dropping modules-extra, is the direct cause of the half kernel).
#    apt-get install is a no-op when already installed — re-run safe.
sudo apt-get update
sudo apt-get install -y --install-recommends "${KERNEL_META}" "${KERNEL_HEADERS_META}"

# 2) Explicitly reinforce modules-extra / headers for the currently booted kernel. The HWE meta only
#    guarantees the kernel it tracks, so the currently booted kernel (possibly GA at install time) needs separate reinforcement.
#    apt-get install is a no-op when already installed — re-run safe.
running="$(uname -r)"
sudo apt-get install -y "linux-modules-extra-${running}" "linux-headers-${running}"

# 3) Verify — check that the net/wireless module directory (holding wifi drivers) exists.
#    Unlike the nvidia gate, this only warns and does not exit: if the HWE meta just installed a new kernel,
#    the currently booted old kernel may legitimately lack the wireless directory (resolved on the new kernel
#    after reboot). The actual gating is handled by install.sh's early check after the reboot return.
if [[ ! -d "/lib/modules/${running}/kernel/drivers/net/wireless" ]]; then
    echo "kernel-baseline: warning — /lib/modules/${running}/.../net/wireless missing." >&2
    echo "  the current kernel (${running}) may be missing modules-extra (affects wifi/USB input)." >&2
fi

echo "kernel-baseline: HWE kernel meta + headers + modules-extra guaranteed (current kernel ${running})."
