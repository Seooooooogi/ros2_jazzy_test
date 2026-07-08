#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/network-static-ip.sh — host 유선 NIC 에 로봇 LAN 용 고정 IP 를 설정 (install.sh step 16).
#
# 로봇 장비 LAN (.1 OnRobot 그리퍼 / .100 로봇 컨트롤러 / .30 host) 과 통신 → host 유선 NIC 가
# 같은 서브넷의 고정 IP 필요. 설정 = NetworkManager (nmcli). gateway/DNS 는 비워 두고
# never-default (기본 경로로 쓰지 않음) 로 설정 → 인터넷 기본 경로(default route)는 wifi 에 그대로 유지
# (이 연결이 기본 경로를 가져가면 인터넷 끊김). 멱등 — 같은 값을 다시 적용해도 변화 없음. 케이블 없어도(no-carrier) 설정 유지.
#
# 단독 실행: bash resources/network-static-ip.sh (IP 가 바뀌면 다시 실행).
# 이 스크립트 = 순수 설치 본문 — state 관리(run_step)는 호출자(install.sh) 담당.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

command -v nmcli >/dev/null || { echo "net: no nmcli — not a NetworkManager environment." >&2; exit 1; }

# --- 1. 유선 NIC 결정 -----------------------------------------
# HOST_ETH_NETIF 가 설정돼 있으면 그대로 사용. 비어 있으면 물리 유선 NIC 를 자동 탐지 (wireless/docker/virtual 제외).
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
        [[ -e "${path}/wireless" ]] && continue   # wireless 제외 — 로봇 LAN 은 유선
        [[ -e "${path}/device" ]]   || continue   # 물리 장치(device symlink 존재)만
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

# --- 2. NetworkManager 연결(connection) 결정 -------------------------
# 활성(active) 연결을 먼저 탐색. 장치가 내려가 있으면(케이블 없음) 활성 연결이 없으므로, 그 NIC 에 묶인
# 저장된 ethernet 프로필(또는 인터페이스 지정이 없는 기본 형태)을 탐색. 둘 다 없으면 새로 생성.
# 기존 프로필을 그 자리에서 수정하는 이유: 경쟁 프로필(예: 기본 'Wired connection 1' 의 DHCP autoconnect)이
# 고정 설정을 덮어쓰는 것을 막기 위함.
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

# --- 3. 고정 IP 적용 (gateway/DNS 없음 → wifi 인터넷 보호) ------------
# interface-name 과 autoconnect 를 함께 핀(고정) → 이 프로필이 그 NIC 에서 확실히 올라오게 함.
nmcli con modify "${conn}" \
    connection.interface-name "${nic}" \
    connection.autoconnect yes \
    ipv4.method manual \
    ipv4.addresses "${HOST_ETH_IP}/${HOST_ETH_PREFIX}" \
    ipv4.gateway "" \
    ipv4.dns "" \
    ipv4.never-default yes
echo "[net] configured: ${HOST_ETH_IP}/${HOST_ETH_PREFIX} (no gateway/DNS, never-default)"

# con up 은 best-effort: 케이블이 없으면(no-carrier) 실패할 수 있지만 설정 자체는 유지.
if nmcli con up "${conn}" >/dev/null 2>&1; then
    echo "[net] connection activated."
else
    echo "[net] warning: failed to activate the connection (cable may be unplugged) — config saved, applied when the cable is connected." >&2
fi

# --- 4. 검증 ----------------------------------------------------------
applied="$(nmcli -g IP4.ADDRESS device show "${nic}" 2>/dev/null | head -1 || true)"
if [[ "${applied}" == "${HOST_ETH_IP}/${HOST_ETH_PREFIX}" ]]; then
    echo "[net] verification OK: ${nic} = ${applied}"
else
    echo "[net] current ${nic} address: ${applied:-(none/down)} (expected ${HOST_ETH_IP}/${HOST_ETH_PREFIX} — may apply once the cable is connected)"
fi
echo "[net] done. The internet default route stays on wifi (this connection is never-default)."
