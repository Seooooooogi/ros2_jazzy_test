#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/hostcfg.sh · 설치 완료된 호스트의 런타임 설정
#   대상 = DDS 버퍼 / 로봇 LAN 정적 IP
#   성격 = 설치 아님, 설정 → 언제든 단독 재실행 가능
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
config_assert_set

# CycloneDDS 설정 XML 렌더 + 커널 소켓 버퍼 증설
hostcfg_dds() {

    local TEMPLATE="${SCRIPT_DIR}/cyclonedds.xml.in"
    local SYSCTL_SRC="${SCRIPT_DIR}/sysctl-cyclonedds.conf"
    SYSCTL_DST="/etc/sysctl.d/60-cyclonedds.conf"

    [[ -f "${TEMPLATE}" ]]   || { echo "dds: template missing: ${TEMPLATE}" >&2; exit 1; }
    [[ -f "${SYSCTL_SRC}" ]] || { echo "dds: sysctl source missing: ${SYSCTL_SRC}" >&2; exit 1; }

    # --- 1. 인터페이스 목록: loopback 기본, 물리 NIC 은 명시 지정만 --------------
    # 다른 머신과 토픽 공유 시에만 DDS_NETIF 로 직접 지정
    declare -a NICS=()
    if [[ -n "${DDS_NETIF}" ]]; then
        # 쉼표로 복수 지정 가능(lo 는 렌더 단계에서 항상 별도 추가)
        IFS=',' read -r -a NICS <<< "${DDS_NETIF}"
        echo "[dds] DDS_NETIF override → external NIC(s): ${NICS[*]}"
    else
        echo "[dds] loopback-only (physical NIC pinning removed). For cross-host ROS2, set DDS_NETIF=<iface[,iface2]>."
    fi

    # --- 2. 재부팅에도 유지되는 sysctl 설치 + 적용 (cyclonedds 노드보다 먼저) ----------------
    echo "[dds] installing kernel socket/fragment buffers: ${SYSCTL_DST}"
    sudo install -m 0644 -o root -g root "${SYSCTL_SRC}" "${SYSCTL_DST}"
    sudo sysctl --system >/dev/null
    echo "[dds]   rmem_max=$(sysctl -n net.core.rmem_max) wmem_max=$(sysctl -n net.core.wmem_max)"

    # --- 3. cyclonedds.xml 렌더링 (NIC 목록 채워 넣기) ------------------------------
    mkdir -p "$(dirname "${CYCLONEDDS_XML}")"
    # 임시 파일 위치 = /tmp 고정(sed 의 r = 경로에 공백 불허)
    iface_block="$(TMPDIR=/tmp mktemp)"
    rendered_xml="$(TMPDIR=/tmp mktemp)"
    trap 'rm -f "${iface_block}" "${rendered_xml}"' EXIT
    {
        # loopback = 항상 맨 앞
        printf '        <NetworkInterface name="lo" priority="default" multicast="true"/>\n'
        for nic in "${NICS[@]}"; do
            [[ "${nic}" == "lo" ]] && continue   # 위에서 이미 추가함 — DDS_NETIF 에 lo 가 들어와도 중복 방지
            printf '        <NetworkInterface name="%s" presence_required="false"/>\n' "${nic}"
        done
    } > "${iface_block}"
    # 자리표시자 줄 하나만 NIC 블록으로 교체
    sed -e "/^__DDS_INTERFACES__\$/{
    r ${iface_block}
    d
    }" "${TEMPLATE}" > "${rendered_xml}"
    mv "${rendered_xml}" "${CYCLONEDDS_XML}"
    echo "[dds] render complete: ${CYCLONEDDS_XML} (loopback + ${#NICS[@]} external NIC)"

    # --- 4. ~/.bashrc 관리 블록 재작성 ----------------------
    # config.sh 적용 범위 = source 된 셸뿐 → 같은 export 를 ~/.bashrc 에도 둔다
    bashrc_sync_block
    echo "[dds] rewrote the ~/.bashrc managed block"

    echo "[dds] done. cyclonedds applies after a new terminal or 'source ~/.bashrc'."
    echo "[dds] note: same-host communication (host↔container) always works via loopback."
    echo "[dds]       communication with other machines requires that external NIC to be up."
}

# 로봇 LAN 쪽 유선 NIC 에 고정 IP 설정(gateway/DNS 공란 + never-default)
hostcfg_network() {

    command -v nmcli >/dev/null || { echo "net: no nmcli — not a NetworkManager environment." >&2; exit 1; }

    # --- 1. 유선 NIC 결정 -----------------------------------------
    # HOST_ETH_NETIF 존재 → 그대로 사용 / 부재 → 물리 유선 NIC 탐색
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
            echo "        bash resources/hostcfg.sh network   (or specify HOST_ETH_NETIF=<iface>)" >&2
            exit 0
        fi
        nic="${found[0]}"
        if [[ "${#found[@]}" -gt 1 ]]; then
            echo "[net] warning: multiple wired NICs (${found[*]}) — using '${nic}'. For precision, specify HOST_ETH_NETIF." >&2
        fi
        echo "[net] wired NIC auto-detect → ${nic}"
    fi

    # --- 2. NetworkManager 연결 결정 -------------------------
    # 탐색 순서 = 활성 연결 → 저장된 ethernet 프로필 → 부재 시 신규 생성
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
    # interface-name + autoconnect 동시 고정 → 이 프로필이 그 NIC 에서 확실히 기동
    nmcli con modify "${conn}" \
        connection.interface-name "${nic}" \
        connection.autoconnect yes \
        ipv4.method manual \
        ipv4.addresses "${HOST_ETH_IP}/${HOST_ETH_PREFIX}" \
        ipv4.gateway "" \
        ipv4.dns "" \
        ipv4.never-default yes
    echo "[net] configured: ${HOST_ETH_IP}/${HOST_ETH_PREFIX} (no gateway/DNS, never-default)"

    # 케이블 미연결 → 활성화 실패 가능(설정은 저장 완료)
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
}

case "${1:?hostcfg: subcommand required (dds|network)}" in
    dds)     hostcfg_dds ;;
    network) hostcfg_network ;;
    *) echo "hostcfg: unknown subcommand '$1'" >&2; exit 2 ;;
esac
