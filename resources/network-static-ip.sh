#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/network-static-ip.sh — set a robot-LAN static IP on the host wired NIC (install.sh step 16).
#
# To communicate on the robot-equipment LAN (.1 OnRobot gripper / .100 robot controller / .30 host), the host
# wired NIC must have a static IP on the same subnet. Configured via NetworkManager (nmcli). No gateway/DNS is
# set and never-default is used, so the internet default route stays on wifi (if this connection grabbed the
# default route, the internet would drop). Idempotent — re-applying the same values is a no-op. The config persists even without a cable (no-carrier).
#
# Standalone run: bash resources/network-static-ip.sh (re-run on IP change).
# This script is a pure install body — the state framing (run_step) is owned by the caller (install.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

command -v nmcli >/dev/null || { echo "net: no nmcli — not a NetworkManager environment." >&2; exit 1; }

# --- 1. determine the wired NIC -----------------------------------------
# Use HOST_ETH_NETIF as-is if set. If empty, auto-detect the physical wired NIC (excluding wireless/docker/virtual).
nic=""
if [[ -n "${HOST_ETH_NETIF}" ]]; then
    nic="${HOST_ETH_NETIF}"
    echo "[net] HOST_ETH_NETIF override → ${nic}"
else
    declare -a found=()
    for path in /sys/class/net/*; do
        n="$(basename "${path}")"
        [[ "${n}" == "lo" ]] && continue
        case "${n}" in docker*|veth*|br-*|virbr*|bond*|tap*|tun*) continue ;; esac
        [[ -e "${path}/wireless" ]] && continue   # exclude wireless — the robot LAN is wired
        [[ -e "${path}/device" ]]   || continue   # physical (device symlink) only
        found+=("${n}")
    done
    if [[ "${#found[@]}" -eq 0 ]]; then
        echo "[net] warning: no physical wired NIC detected — skipping the static IP setup (this step is recorded as complete)." >&2
        echo "      After connecting a NIC (USB-ethernet, etc.), re-run this script standalone to apply it:" >&2
        echo "        bash resources/network-static-ip.sh   (or specify HOST_ETH_NETIF=<iface>)" >&2
        exit 0
    fi
    nic="${found[0]}"
    if [[ "${#found[@]}" -gt 1 ]]; then
        echo "[net] warning: multiple wired NICs (${found[*]}) — using '${nic}'. For precision, specify HOST_ETH_NETIF." >&2
    fi
    echo "[net] wired NIC auto-detect → ${nic}"
fi

# --- 2. determine the NetworkManager connection -------------------------
# Active connection first. If the device is down (no cable), there is no active connection, so find a saved
# ethernet profile bound to that NIC (or the default form with no interface specified). Create one if neither exists.
# Modify the existing profile in place to prevent a competing profile (e.g. the default 'Wired connection 1' DHCP autoconnect)
# from overriding the static config.
conn="$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null | awk -F: -v d="${nic}" '$2==d{print $1; exit}')"
if [[ -z "${conn}" ]]; then
    while IFS= read -r name; do
        [[ -z "${name}" ]] && continue
        [[ "$(nmcli -g connection.type con show "${name}" 2>/dev/null)" == "802-3-ethernet" ]] || continue
        ifn="$(nmcli -g connection.interface-name con show "${name}" 2>/dev/null)"
        if [[ "${ifn}" == "${nic}" || -z "${ifn}" ]]; then conn="${name}"; break; fi
    done < <(nmcli -t -f NAME con show 2>/dev/null)
fi
if [[ -z "${conn}" ]]; then
    conn="${nic}-static"
    echo "[net] no ethernet profile for '${nic}', creating one: ${conn}"
    nmcli con add type ethernet ifname "${nic}" con-name "${conn}" >/dev/null
fi
echo "[net] target connection: ${conn} (device ${nic})"

# --- 3. apply the static IP (no gateway/DNS → protect wifi internet) ------------
# Pin interface-name and autoconnect together so this profile reliably comes up on that NIC.
nmcli con modify "${conn}" \
    connection.interface-name "${nic}" \
    connection.autoconnect yes \
    ipv4.method manual \
    ipv4.addresses "${HOST_ETH_IP}/${HOST_ETH_PREFIX}" \
    ipv4.gateway "" \
    ipv4.dns "" \
    ipv4.never-default yes
echo "[net] configured: ${HOST_ETH_IP}/${HOST_ETH_PREFIX} (no gateway/DNS, never-default)"

# con up is best-effort: it may fail without a cable (no-carrier), but the config persists.
if nmcli con up "${conn}" >/dev/null 2>&1; then
    echo "[net] connection activated."
else
    echo "[net] warning: failed to activate the connection (cable may be unplugged) — config saved, applied when the cable is connected." >&2
fi

# --- 4. verify ----------------------------------------------------------
applied="$(nmcli -g IP4.ADDRESS device show "${nic}" 2>/dev/null | head -1 || true)"
if [[ "${applied}" == "${HOST_ETH_IP}/${HOST_ETH_PREFIX}" ]]; then
    echo "[net] verification OK: ${nic} = ${applied}"
else
    echo "[net] current ${nic} address: ${applied:-(none/down)} (expected ${HOST_ETH_IP}/${HOST_ETH_PREFIX} — may apply once the cable is connected)"
fi
echo "[net] done. The internet default route stays on wifi (this connection is never-default)."
