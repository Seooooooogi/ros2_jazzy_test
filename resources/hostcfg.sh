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

# loopback 을 항상 맨 앞에 둬 같은 호스트 노드끼리 자기 자신에게 unicast 하다 실패하는 상황을 막고, 커널 소켓 버퍼는 cyclonedds 노드가 뜨기 전에 sysctl 로 먼저 늘려 둔다.
hostcfg_dds() {

    local TEMPLATE="${SCRIPT_DIR}/cyclonedds.xml.in"
    local SYSCTL_SRC="${SCRIPT_DIR}/sysctl-cyclonedds.conf"
    SYSCTL_DST="/etc/sysctl.d/60-cyclonedds.conf"

    [[ -f "${TEMPLATE}" ]]   || { echo "dds-tuning: template missing: ${TEMPLATE}" >&2; exit 1; }
    [[ -f "${SYSCTL_SRC}" ]] || { echo "dds-tuning: sysctl source missing: ${SYSCTL_SRC}" >&2; exit 1; }

    # --- 1. 인터페이스 목록: loopback 기본, 물리 NIC 은 명시 지정만 --------------
    # 물리 NIC 자동 고정은 제거했다(2026-07-23). 이 시스템의 ROS2 DDS 참여자는 전부 같은 호스트다
    # (host + network_mode:host 컨테이너); 실 로봇은 DSR 드라이버의 TCP 로 붙지 DDS 참여자가 아니다.
    # 따라서 loopback 하나로 충분하다. 자동 감지는 머신에 따라 빈 NIC 이름(name="")을 렌더해
    # cyclonedds 가 "Nameless and address-less interface" 로 도메인 생성을 통째로 거부(rmw_create_node
    # failed → 모든 노드 즉사)하는 사고를 냈다 — 그 위험을 원천 제거한다.
    # 다른 머신의 ROS2 노드와 토픽을 나눠야 하는 드문 cross-host 경우에만 DDS_NETIF 로 명시 지정.
    declare -a NICS=()
    if [[ -n "${DDS_NETIF}" ]]; then
        # override: 쉼표로 구분해 여러 개 지정 가능. lo 는 렌더 단계에서 항상 따로 추가되므로
        # 여기엔 외부 NIC 만 기입 (lo 넣어도 중복 방지 가드 존재).
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
    # 임시 파일을 /tmp 로 고정 — sed 의 `r` 명령은 파일명을 따옴표로 감쌀 수 없음 → 공백 없는 경로 필수.
    iface_block="$(TMPDIR=/tmp mktemp)"
    rendered_xml="$(TMPDIR=/tmp mktemp)"
    trap 'rm -f "${iface_block}" "${rendered_xml}"' EXIT
    {
        # loopback 을 항상 맨 앞에 — 같은 호스트 안의 데이터 경로 (외부 IP 로 자기 자신에게 보내는 걸 우회).
        # priority="default" → cyclonedds 가 loopback 에 더 높은 우선순위 부여 → 같은 호스트끼리
        # 매칭 시 127.0.0.1 사용 (실측: writer 의 addrset 이 udp/127.0.0.1 로 해석됨).
        printf '        <NetworkInterface name="lo" priority="default" multicast="true"/>\n'
        for nic in "${NICS[@]}"; do
            [[ "${nic}" == "lo" ]] && continue   # 위에서 이미 추가함 — DDS_NETIF 에 lo 가 들어와도 중복 방지
            printf '        <NetworkInterface name="%s" presence_required="false"/>\n' "${nic}"
        done
    } > "${iface_block}"
    # 자리표시자(placeholder) 줄 하나만 NIC 블록으로 교체 (sed r 이 파일 삽입 후 그 줄 삭제).
    # ^...$ 로 줄 전체 고정(anchor) → 같은 토큰이 주석 본문에 나와도 오매칭 방지.
    # 먼저 임시 파일에 렌더링 후 atomic mv 로 이동 — sed 가 도중 실패해도 기존 XML(또는 파일 없음) 을
    # 반쪽짜리 XML 로 덮어쓰지 않음 (반쪽 XML = cyclonedds 노드 즉사).
    sed -e "/^__DDS_INTERFACES__\$/{
    r ${iface_block}
    d
    }" "${TEMPLATE}" > "${rendered_xml}"
    mv "${rendered_xml}" "${CYCLONEDDS_XML}"
    echo "[dds] render complete: ${CYCLONEDDS_XML} (loopback + ${#NICS[@]} external NIC)"

    # --- 4. ~/.bashrc 환경변수 멱등 주입 (관리 블록 하나로 통합) ----------------------
    # config.sh 는 source 되는 상황(activate.sh/CI) 에서만 적용, 대화형 셸(interactive shell) 은
    # ~/.bashrc 만 읽음 → export 를 여기에 삽입. 먼저 기존 관리 줄(수동 삽입분 포함) 제거 후,
    # 마커(marker) 블록으로 재기록 → 중복 방지 (멱등).
    bashrc="${HOME}/.bashrc"
    BEGIN_MARK="# >>> ros2_jazzy_test cyclonedds env >>>"
    END_MARK="# <<< ros2_jazzy_test cyclonedds env <<<"
    if [[ -f "${bashrc}" ]]; then
        # 이전 관리 블록 제거
        sed -i "/${BEGIN_MARK}/,/${END_MARK}/d" "${bashrc}"
        # 이번 세션에 수동으로 들어갔을 수 있는 흩어진 export/주석 정리
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
        # ROS_DOMAIN_ID 은 일부러 여기서 관리 안 함 — 학생이 직접 자기 ~/.bashrc 에
        # `export ROS_DOMAIN_ID=<n>` 추가 (학습 과제). 아무 데도 설정 안 하면 → host 와 컨테이너 둘 다 0(ROS2 기본값) 으로
        # 떨어져 여전히 서로 매칭됨; compose 는 bringup 시 셸이 export 한 값(config.sh 경유) 을 가져감.
        echo "${END_MARK}"
    } >> "${bashrc}"
    echo "[dds] updated the ~/.bashrc managed block (CYCLONEDDS_URI / RMW_IMPLEMENTATION)"

    echo "[dds] done. cyclonedds applies after a new terminal or 'source ~/.bashrc'."
    echo "[dds] note: same-host communication (host↔container) always works via loopback."
    echo "[dds]       communication with other machines requires that external NIC to be up."
}

# gateway/DNS 를 비우고 never-default 로 설정해, 로봇 LAN 고정 IP 를 잡아도 인터넷 기본 경로는 wifi 에 그대로 둔다.
hostcfg_network() {

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
}

case "${1:?hostcfg: subcommand required (dds|network)}" in
    dds)     hostcfg_dds ;;
    network) hostcfg_network ;;
    *) echo "hostcfg: unknown subcommand '$1'" >&2; exit 2 ;;
esac
