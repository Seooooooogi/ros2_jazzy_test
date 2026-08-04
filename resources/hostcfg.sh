#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/hostcfg.sh — 설치가 끝난 호스트의 런타임 설정(DDS 버퍼 / 로봇 LAN 정적 IP).
# 설치가 아니라 설정이라 언제든 단독으로 다시 돌려도 된다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

# CycloneDDS 설정 XML 을 렌더하고 커널 소켓 버퍼를 늘린다.
# 버퍼를 sysctl 로 먼저 키워 두는 이유: cyclonedds 노드는 뜨는 순간의 버퍼 크기를 그대로 가져간다.
hostcfg_dds() {

    local TEMPLATE="${SCRIPT_DIR}/cyclonedds.xml.in"
    local SYSCTL_SRC="${SCRIPT_DIR}/sysctl-cyclonedds.conf"
    SYSCTL_DST="/etc/sysctl.d/60-cyclonedds.conf"

    [[ -f "${TEMPLATE}" ]]   || { echo "dds: template missing: ${TEMPLATE}" >&2; exit 1; }
    [[ -f "${SYSCTL_SRC}" ]] || { echo "dds: sysctl source missing: ${SYSCTL_SRC}" >&2; exit 1; }

    # --- 1. 인터페이스 목록: loopback 기본, 물리 NIC 은 명시 지정만 --------------
    # 이 시스템의 DDS 참여자는 전부 같은 호스트에 있다(host + network_mode:host 컨테이너) — 실 로봇은
    # DSR 드라이버의 TCP 로 붙지 DDS 참여자가 아니다. 그래서 loopback 하나면 충분하다.
    # 물리 NIC 자동 감지는 머신에 따라 빈 이름을 렌더해 cyclonedds 가 도메인 생성을 통째로 거부하고
    # 모든 노드가 즉사한 적이 있어 없앴다. 다른 머신과 토픽을 나눌 때만 DDS_NETIF 로 직접 지정한다.
    declare -a NICS=()
    if [[ -n "${DDS_NETIF}" ]]; then
        # 쉼표로 여러 개 지정 가능. lo 는 렌더 단계에서 항상 따로 붙으므로 외부 NIC 만 적으면 된다.
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
    # 임시 파일은 /tmp 로 고정한다 — sed 의 `r` 은 파일명을 따옴표로 감쌀 수 없어 공백이 없어야 한다.
    iface_block="$(TMPDIR=/tmp mktemp)"
    rendered_xml="$(TMPDIR=/tmp mktemp)"
    trap 'rm -f "${iface_block}" "${rendered_xml}"' EXIT
    {
        # loopback 을 항상 맨 앞에. 우선순위를 높여 두면 같은 호스트끼리는 127.0.0.1 로 주고받는다.
        printf '        <NetworkInterface name="lo" priority="default" multicast="true"/>\n'
        for nic in "${NICS[@]}"; do
            [[ "${nic}" == "lo" ]] && continue   # 위에서 이미 추가함 — DDS_NETIF 에 lo 가 들어와도 중복 방지
            printf '        <NetworkInterface name="%s" presence_required="false"/>\n' "${nic}"
        done
    } > "${iface_block}"
    # 자리표시자 줄 하나만 NIC 블록으로 갈아 끼운다(줄 전체를 고정해 주석 본문과 오매칭하지 않게).
    # 임시 파일에 먼저 렌더하고 mv 로 옮기는 이유: sed 가 도중에 실패해도 반쪽짜리 XML 이 남지
    # 않게 하려는 것 — 깨진 XML 을 만나면 cyclonedds 노드가 그대로 죽는다.
    sed -e "/^__DDS_INTERFACES__\$/{
    r ${iface_block}
    d
    }" "${TEMPLATE}" > "${rendered_xml}"
    mv "${rendered_xml}" "${CYCLONEDDS_XML}"
    echo "[dds] render complete: ${CYCLONEDDS_XML} (loopback + ${#NICS[@]} external NIC)"

    # --- 4. ~/.bashrc 환경변수 주입 (관리 블록 하나로) ----------------------
    # config.sh 는 source 될 때만 적용되는데 사용자가 여는 대화형 셸은 ~/.bashrc 만 읽는다 —
    # 그래서 같은 export 를 여기에도 넣는다. 기존 줄을 지우고 마커 블록으로 다시 써서 중복을 막는다.
    bashrc="${HOME}/.bashrc"
    BEGIN_MARK="# >>> ros2_jazzy_test cyclonedds env >>>"
    END_MARK="# <<< ros2_jazzy_test cyclonedds env <<<"
    if [[ -f "${bashrc}" ]]; then
        # 이전 관리 블록 제거
        sed -i "/${BEGIN_MARK}/,/${END_MARK}/d" "${bashrc}"
        # 예전에 손으로 넣었을 수 있는 흩어진 export/주석도 함께 정리
        sed -i \
            -e '/CycloneDDS receive-buffer tuning for large RealSense topics/d' \
            -e '/default RMW = CycloneDDS for all new shells/d' \
            -e '\#^export CYCLONEDDS_URI=#d' \
            -e '/^export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp/d' \
            "${bashrc}"
    fi
    {
        echo "${BEGIN_MARK}"
        echo "# CycloneDDS standard + large-topic buffer/interface tuning (managed by hostcfg.sh dds, do not edit manually)"
        echo "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp"
        echo "export CYCLONEDDS_URI=\"file://${CYCLONEDDS_XML}\""
        # ROS_DOMAIN_ID 는 일부러 여기서 관리하지 않는다 — 학생이 직접 자기 ~/.bashrc 에 추가하는
        # 연습 과제다. 아무 데도 없으면 host 와 컨테이너 모두 기본값 0 이라 서로 매칭된다.
        echo "${END_MARK}"
    } >> "${bashrc}"
    echo "[dds] updated the ~/.bashrc managed block (CYCLONEDDS_URI / RMW_IMPLEMENTATION)"

    echo "[dds] done. cyclonedds applies after a new terminal or 'source ~/.bashrc'."
    echo "[dds] note: same-host communication (host↔container) always works via loopback."
    echo "[dds]       communication with other machines requires that external NIC to be up."
}

# 로봇 LAN 쪽 유선 NIC 에 고정 IP 를 잡는다.
# gateway/DNS 를 비우고 never-default 로 두어 인터넷 기본 경로는 wifi 에 그대로 남긴다.
hostcfg_network() {

    command -v nmcli >/dev/null || { echo "net: no nmcli — not a NetworkManager environment." >&2; exit 1; }

    # --- 1. 유선 NIC 결정 -----------------------------------------
    # HOST_ETH_NETIF 가 있으면 그대로, 없으면 물리 유선 NIC 를 찾는다(무선/docker/가상 인터페이스 제외).
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
    # 활성 연결 → 그 NIC 에 저장된 ethernet 프로필 → 없으면 새로 생성 순으로 찾는다(케이블이 빠져 있으면
    # 활성 연결이 없다). 새로 만들지 않고 기존 프로필을 고치는 이유는, 남아 있는 DHCP 프로필이 자동으로
    # 올라와 방금 넣은 고정 설정을 덮어쓰는 것을 막기 위해서다.
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
    # interface-name 과 autoconnect 를 함께 고정해 이 프로필이 그 NIC 에서 확실히 올라오게 한다.
    nmcli con modify "${conn}" \
        connection.interface-name "${nic}" \
        connection.autoconnect yes \
        ipv4.method manual \
        ipv4.addresses "${HOST_ETH_IP}/${HOST_ETH_PREFIX}" \
        ipv4.gateway "" \
        ipv4.dns "" \
        ipv4.never-default yes
    echo "[net] configured: ${HOST_ETH_IP}/${HOST_ETH_PREFIX} (no gateway/DNS, never-default)"

    # 케이블이 꽂혀 있지 않으면 활성화는 실패할 수 있다 — 설정 자체는 저장돼 있으니 그대로 진행한다.
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
