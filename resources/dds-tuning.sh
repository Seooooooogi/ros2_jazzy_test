#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/dds-tuning.sh — CycloneDDS large-topic tuning install (install.sh step 13).
#
# What it does (order matters — sysctl must come before cyclonedds nodes start):
#   1. auto-detect the install machine's physical external NICs (both wired and wireless, excluding docker/virtual, regardless of carrier).
#   2. install + apply /etc/sysctl.d/60-cyclonedds.conf (persistent socket/fragment buffers).
#   3. render to ${CYCLONEDDS_XML} by substituting loopback + the NIC list into the cyclonedds.xml.in template.
#   4. idempotently inject CYCLONEDDS_URI / RMW_IMPLEMENTATION exports into ~/.bashrc.
#
# Interface policy: always put loopback (lo) first (between same-host nodes cyclonedds
# prefers loopback → 127.0.0.1, avoiding external-IP unicast-to-self routing failure); the physical external NICs
# are also whitelisted for the cross-host path to other machines.
#
# Standalone run: bash resources/dds-tuning.sh (re-run on hardware change to refresh the list).
# This script is a pure install body — the state framing (run_step) is owned by the caller (install.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

TEMPLATE="${SCRIPT_DIR}/cyclonedds.xml.in"
SYSCTL_SRC="${SCRIPT_DIR}/sysctl-cyclonedds.conf"
SYSCTL_DST="/etc/sysctl.d/60-cyclonedds.conf"

[[ -f "${TEMPLATE}" ]]   || { echo "dds-tuning: template missing: ${TEMPLATE}" >&2; exit 1; }
[[ -f "${SYSCTL_SRC}" ]] || { echo "dds-tuning: sysctl source missing: ${SYSCTL_SRC}" >&2; exit 1; }

# --- 1. physical external NIC detection (wired + wireless) --------------
# A physical NIC exists in /sys/class/net even without carrier/IP, so it is identifiable on a robot-less install too.
# Exclude virtual (no device symlink) and docker/veth/bridge/tap/tun — they are not paths to other machines and
# only add useless locators, causing discovery noise / -1 send failures. lo is always added separately
# at the front in the render step, so it is excluded from this list.
declare -a NICS=()
if [[ -n "${DDS_NETIF}" ]]; then
    # override: comma-separated allowed. Used as-is at the user's responsibility. lo is always
    # added separately in the render step, so specify only external NICs here (a guard prevents duplicates even if lo is included).
    IFS=',' read -r -a NICS <<< "${DDS_NETIF}"
    echo "[dds] DDS_NETIF override → ${NICS[*]}"
else
    for path in /sys/class/net/*; do
        nic="$(basename "${path}")"
        [[ "${nic}" == "lo" ]] && continue
        case "${nic}" in docker*|veth*|br-*|virbr*|bond*|tap*|tun*) continue ;; esac
        [[ -e "${path}/device" ]] || continue   # physical (device symlink) only — both wired/wireless
        NICS+=("${nic}")
    done
    if [[ "${#NICS[@]}" -eq 0 ]]; then
        # Even with 0 external NICs, loopback alone works for the same host (host↔container) →
        # not fatal (it was exit 1 before, but the policy changed to always add lo).
        echo "[dds] warning: no physical external NIC detected — only same-host communication is configured via loopback." >&2
        echo "       If cross-host communication with other machines is needed, specify the interface explicitly:" >&2
        echo "       DDS_NETIF=<iface[,iface2]> bash resources/dds-tuning.sh" >&2
    else
        echo "[dds] external NIC auto-detect → ${NICS[*]} (docker/virtual excluded; loopback always added)"
    fi
fi

# --- 2. persistent sysctl install + apply (before cyclonedds nodes) ----------------
echo "[dds] installing kernel socket/fragment buffers: ${SYSCTL_DST}"
sudo install -m 0644 -o root -g root "${SYSCTL_SRC}" "${SYSCTL_DST}"
sudo sysctl --system >/dev/null
echo "[dds]   rmem_max=$(sysctl -n net.core.rmem_max) wmem_max=$(sysctl -n net.core.wmem_max)"

# --- 3. render cyclonedds.xml (substitute the NIC list) ------------------------------
mkdir -p "$(dirname "${CYCLONEDDS_XML}")"
# temp file fixed to /tmp — sed's `r` command cannot quote the filename, so ensure a space-free path.
iface_block="$(TMPDIR=/tmp mktemp)"
rendered_xml="$(TMPDIR=/tmp mktemp)"
trap 'rm -f "${iface_block}" "${rendered_xml}"' EXIT
{
    # loopback always first — same-host data path (bypass external-IP unicast-to-self).
    # with priority="default", cyclonedds gives loopback higher priority, using 127.0.0.1 for
    # same-host matches (measured: the writer addrset resolves to udp/127.0.0.1).
    printf '        <NetworkInterface name="lo" priority="default" multicast="true"/>\n'
    for nic in "${NICS[@]}"; do
        [[ "${nic}" == "lo" ]] && continue   # already added above — prevents duplication even if lo comes in DDS_NETIF
        printf '        <NetworkInterface name="%s" presence_required="false"/>\n' "${nic}"
    done
} > "${iface_block}"
# replace only the placeholder line (standalone) with the NIC block (sed r inserts the file then deletes it).
# anchor ^...$ so it does not mismatch even if the same token appears in a comment body.
# render to the temp file first then atomic mv — so even if sed fails midway, it does not overwrite the existing XML
# (or no file) with a partial XML (a partial XML kills cyclonedds nodes instantly).
sed -e "/^__DDS_INTERFACES__\$/{
r ${iface_block}
d
}" "${TEMPLATE}" > "${rendered_xml}"
mv "${rendered_xml}" "${CYCLONEDDS_XML}"
echo "[dds] render complete: ${CYCLONEDDS_XML} (loopback + ${#NICS[@]} external)"

# --- 4. idempotent ~/.bashrc env injection (unified into a managed block) ----------------------
# config.sh applies only in sourced contexts (activate.sh/CI), and an interactive shell
# reads only ~/.bashrc, so we plant the exports here. Remove existing managed lines (including manual ones) first,
# then rewrite as a marker block to prevent duplicates (idempotent).
bashrc="${HOME}/.bashrc"
BEGIN_MARK="# >>> ros2_jazzy_test cyclonedds env >>>"
END_MARK="# <<< ros2_jazzy_test cyclonedds env <<<"
if [[ -f "${bashrc}" ]]; then
    # remove the previous managed block
    sed -i "/${BEGIN_MARK}/,/${END_MARK}/d" "${bashrc}"
    # clean up sporadic export/comment that may have been manually added this session
    sed -i \
        -e '/CycloneDDS receive-buffer tuning for large RealSense topics/d' \
        -e '/default RMW = CycloneDDS for all new shells/d' \
        -e '\#^export CYCLONEDDS_URI=#d' \
        -e '/^export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp/d' \
        "${bashrc}"
fi
{
    echo "${BEGIN_MARK}"
    echo "# CycloneDDS standard + large-topic buffer/interface tuning (managed by dds-tuning.sh, do not edit manually)"
    echo "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp"
    echo "export CYCLONEDDS_URI=\"file://${CYCLONEDDS_XML}\""
    # ROS_DOMAIN_ID is read from the persisted file at shell start (not baked), so the value chosen later in
    # setup-app takes effect in new terminals without re-running dds-tuning. Single-quoted so this line is
    # written verbatim and the command substitution runs in the user's shell, not here.
    # shellcheck disable=SC2016  # single quotes are intentional: the line stays literal in ~/.bashrc.
    # Second assignment mirrors config.sh's `:-42` guard so a missing OR empty file both fall back to 42.
    echo 'export ROS_DOMAIN_ID="$(cat "${XDG_CONFIG_HOME:-$HOME/.config}/ros2_jazzy_test/ros_domain_id" 2>/dev/null)"; export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-42}"'
    echo "${END_MARK}"
} >> "${bashrc}"
echo "[dds] updated the ~/.bashrc managed block (CYCLONEDDS_URI / RMW_IMPLEMENTATION / ROS_DOMAIN_ID)"

echo "[dds] done. cyclonedds applies after a new terminal or 'source ~/.bashrc'."
echo "[dds] note: same-host communication (host↔container) always works via loopback."
echo "[dds]       communication with other machines requires that external NIC to be up."
