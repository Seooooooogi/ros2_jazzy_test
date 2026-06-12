#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/network-static-ip.sh — host 유선 NIC 에 로봇 LAN 고정 IP 설정 (install.sh step 16).
#
# 로봇 장비 LAN(.1 OnRobot 그리퍼 / .100 로봇 컨트롤러 / .30 host)에서 통신하려면 host 유선
# NIC 가 같은 서브넷의 고정 IP 여야 한다. NetworkManager(nmcli)로 설정한다. 게이트웨이/DNS 는
# 두지 않고 never-default 로 둬, 인터넷 기본 경로는 wifi 가 유지하게 한다(이 연결이 기본 경로를
# 잡으면 인터넷 끊김). 멱등 — 같은 값 재적용은 no-op. 케이블 미연결(no-carrier)이어도 설정은 영속.
#
# 단독 실행 가능: bash resources/network-static-ip.sh (IP 변경 시 재실행).
# 본 스크립트는 순수 설치 본문 — state 프레이밍(run_step)은 호출자(install.sh)가 소유.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

command -v nmcli >/dev/null || { echo "net: nmcli 없음 — NetworkManager 환경이 아닙니다." >&2; exit 1; }

# --- 1. 유선 NIC 결정 ----------------------------------------------------
# HOST_ETH_NETIF 지정 시 그대로. 빈값이면 물리 유선 NIC 자동 탐지(무선/docker/가상 제외).
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
        [[ -e "${path}/wireless" ]] && continue   # 무선 제외 — 로봇 LAN 은 유선
        [[ -e "${path}/device" ]]   || continue   # 물리(device 심볼릭)만
        found+=("${n}")
    done
    if [[ "${#found[@]}" -eq 0 ]]; then
        echo "[net] 경고: 물리 유선 NIC 미검출 — 고정 IP 설정을 건너뜁니다(이 step 은 완료로 기록됨)." >&2
        echo "      NIC(USB-이더넷 등) 연결 후 이 스크립트를 단독 재실행하면 적용됩니다:" >&2
        echo "        bash resources/network-static-ip.sh   (또는 HOST_ETH_NETIF=<iface> 지정)" >&2
        exit 0
    fi
    nic="${found[0]}"
    if [[ "${#found[@]}" -gt 1 ]]; then
        echo "[net] 경고: 유선 NIC 가 여러 개(${found[*]}) — '${nic}' 사용. 정확히 하려면 HOST_ETH_NETIF 지정." >&2
    fi
    echo "[net] 유선 NIC 자동 탐지 → ${nic}"
fi

# --- 2. NetworkManager 연결 결정 ----------------------------------------
# 활성 연결 우선. device 가 down(케이블 미연결)이면 활성 연결이 없으므로, 그 NIC 에 묶인
# (또는 인터페이스 미지정 기본형) 저장된 ethernet 프로필을 찾는다. 둘 다 없으면 생성한다.
# 기존 프로필을 그대로 수정해, 경쟁 프로필(예: 기본 'Wired connection 1' 의 DHCP 자동연결)이
# 정적 설정을 덮어쓰는 것을 막는다.
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
    echo "[net] '${nic}' 에 ethernet 프로필이 없어 새로 만듭니다: ${conn}"
    nmcli con add type ethernet ifname "${nic}" con-name "${conn}" >/dev/null
fi
echo "[net] 대상 연결: ${conn} (device ${nic})"

# --- 3. 고정 IP 적용 (게이트웨이/DNS 없음 → wifi 인터넷 보호) ------------
# interface-name·autoconnect 를 함께 핀해, 이 프로필이 해당 NIC 에서 확실히 올라오게 한다.
nmcli con modify "${conn}" \
    connection.interface-name "${nic}" \
    connection.autoconnect yes \
    ipv4.method manual \
    ipv4.addresses "${HOST_ETH_IP}/${HOST_ETH_PREFIX}" \
    ipv4.gateway "" \
    ipv4.dns "" \
    ipv4.never-default yes
echo "[net] 설정: ${HOST_ETH_IP}/${HOST_ETH_PREFIX} (gateway/DNS 없음, never-default)"

# con up 은 best-effort: 케이블 미연결(no-carrier)이면 실패할 수 있으나 설정은 영속.
if nmcli con up "${conn}" >/dev/null 2>&1; then
    echo "[net] 연결 활성화 완료."
else
    echo "[net] 경고: 연결 활성화 실패(케이블 미연결 가능) — 설정은 저장됨, 케이블 연결 시 적용." >&2
fi

# --- 4. 검증 ------------------------------------------------------------
applied="$(nmcli -g IP4.ADDRESS device show "${nic}" 2>/dev/null | head -1 || true)"
if [[ "${applied}" == "${HOST_ETH_IP}/${HOST_ETH_PREFIX}" ]]; then
    echo "[net] 검증 OK: ${nic} = ${applied}"
else
    echo "[net] 현재 ${nic} 주소: ${applied:-(없음/down)} (기대 ${HOST_ETH_IP}/${HOST_ETH_PREFIX} — 케이블 연결 후 반영될 수 있음)"
fi
echo "[net] 완료. 인터넷 기본 경로는 wifi 유지(이 연결은 never-default)."
