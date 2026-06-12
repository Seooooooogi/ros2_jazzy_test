#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/dds-tuning.sh — CycloneDDS 대용량 토픽 튜닝 설치 (install.sh step 13).
#
# 하는 일 (순서 중요 — sysctl 이 cyclonedds 노드 기동보다 먼저여야 함):
#   1. 설치 머신의 물리 외부 NIC 자동 탐지 (유선·무선 모두, docker/가상 제외, carrier 무관).
#   2. /etc/sysctl.d/60-cyclonedds.conf 설치 + 적용 (소켓/fragment 버퍼 영속).
#   3. cyclonedds.xml.in 템플릿에 loopback + NIC 목록을 치환해 ${CYCLONEDDS_XML} 로 렌더.
#   4. ~/.bashrc 에 CYCLONEDDS_URI / RMW_IMPLEMENTATION export 멱등 주입.
#
# 인터페이스 정책: loopback(lo) 을 항상 선두에 두고(같은 호스트 노드끼리는 cyclonedds 가
# loopback 우선 → 127.0.0.1, 외부 IP unicast-to-self 라우팅 실패 회피) 물리 외부 NIC 는
# 다른 머신과의 cross-host 경로로 함께 화이트리스트한다.
#
# 단독 실행 가능: bash resources/dds-tuning.sh (하드웨어 변경 시 재실행으로 목록 갱신).
# 본 스크립트는 순수 설치 본문 — state 프레이밍(run_step)은 호출자(install.sh)가 소유.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

TEMPLATE="${SCRIPT_DIR}/cyclonedds.xml.in"
SYSCTL_SRC="${SCRIPT_DIR}/sysctl-cyclonedds.conf"
SYSCTL_DST="/etc/sysctl.d/60-cyclonedds.conf"

[[ -f "${TEMPLATE}" ]]   || { echo "dds-tuning: 템플릿 없음: ${TEMPLATE}" >&2; exit 1; }
[[ -f "${SYSCTL_SRC}" ]] || { echo "dds-tuning: sysctl 원본 없음: ${SYSCTL_SRC}" >&2; exit 1; }

# --- 1. 물리 외부 NIC 탐지 (유선 + 무선) --------------------------------
# 물리 NIC 는 carrier/IP 없어도 /sys/class/net 에 존재하므로 로봇 미연결 설치에도 식별 가능.
# 가상(device 심볼릭 부재)·docker/veth/bridge/tap/tun 는 제외 — 타 머신 경로가 아니고
# 쓸모없는 locator 만 늘려 discovery 노이즈/-1 송신실패를 만든다. lo 는 렌더 단계에서
# 항상 별도 선두 추가하므로 여기 목록에선 제외한다.
declare -a NICS=()
if [[ -n "${DDS_NETIF}" ]]; then
    # override: 콤마구분 허용. 사용자 책임으로 그대로 사용. lo 는 렌더 단계에서 항상
    # 별도 추가되므로 여기엔 외부 NIC 만 지정하면 된다(lo 를 넣어도 중복은 가드로 방지).
    IFS=',' read -r -a NICS <<< "${DDS_NETIF}"
    echo "[dds] DDS_NETIF override → ${NICS[*]}"
else
    for path in /sys/class/net/*; do
        nic="$(basename "${path}")"
        [[ "${nic}" == "lo" ]] && continue
        case "${nic}" in docker*|veth*|br-*|virbr*|bond*|tap*|tun*) continue ;; esac
        [[ -e "${path}/device" ]] || continue   # 물리(device 심볼릭)만 — 유선/무선 모두
        NICS+=("${nic}")
    done
    if [[ "${#NICS[@]}" -eq 0 ]]; then
        # 외부 NIC 가 0개여도 loopback 단독으로 같은 호스트(호스트↔컨테이너)는 동작 →
        # 치명적 아님(과거엔 exit 1 이었으나, lo 항상 추가로 정책 변경).
        echo "[dds] 경고: 물리 외부 NIC 미검출 — loopback 으로 same-host 통신만 구성됩니다." >&2
        echo "       다른 머신과의 cross-host 통신이 필요하면 인터페이스를 직접 지정하세요:" >&2
        echo "       DDS_NETIF=<iface[,iface2]> bash resources/dds-tuning.sh" >&2
    else
        echo "[dds] 외부 NIC 자동 탐지 → ${NICS[*]} (docker/가상 제외; loopback 은 항상 추가)"
    fi
fi

# --- 2. sysctl 영속 설치 + 적용 (cyclonedds 노드보다 먼저) ----------------
echo "[dds] 커널 소켓/fragment 버퍼 설치: ${SYSCTL_DST}"
sudo install -m 0644 -o root -g root "${SYSCTL_SRC}" "${SYSCTL_DST}"
sudo sysctl --system >/dev/null
echo "[dds]   rmem_max=$(sysctl -n net.core.rmem_max) wmem_max=$(sysctl -n net.core.wmem_max)"

# --- 3. cyclonedds.xml 렌더 (NIC 목록 치환) ------------------------------
mkdir -p "$(dirname "${CYCLONEDDS_XML}")"
# 임시파일은 /tmp 고정 — sed 의 `r` 명령은 파일명을 인용 못 하므로 공백 없는 경로 보장.
iface_block="$(TMPDIR=/tmp mktemp)"
rendered_xml="$(TMPDIR=/tmp mktemp)"
trap 'rm -f "${iface_block}" "${rendered_xml}"' EXIT
{
    # loopback 항상 선두 — 같은 호스트 데이터 경로(외부 IP unicast-to-self 우회).
    # priority="default" 면 cyclonedds 가 loopback 에 더 높은 우선순위를 줘, 같은 호스트
    # 매칭엔 127.0.0.1 을 쓴다(실측 확인: writer addrset 이 udp/127.0.0.1 로 해석됨).
    printf '        <NetworkInterface name="lo" priority="default" multicast="true"/>\n'
    for nic in "${NICS[@]}"; do
        [[ "${nic}" == "lo" ]] && continue   # 위에서 이미 추가 — DDS_NETIF 에 lo 가 와도 중복 방지
        printf '        <NetworkInterface name="%s" presence_required="false"/>\n' "${nic}"
    done
} > "${iface_block}"
# placeholder 줄(단독 줄)만 NIC 블록으로 치환 (sed r 로 파일 삽입 후 삭제).
# 앵커 ^...$ 로 주석 본문에 같은 토큰이 있어도 오매칭하지 않게 한다.
# 임시파일에 먼저 렌더 후 원자적 mv — sed 가 중간 실패해도 기존 XML(또는 무파일)을
# 부분 XML 로 덮어쓰지 않는다(부분 XML 이면 cyclonedds 노드가 즉사).
sed -e "/^__DDS_INTERFACES__\$/{
r ${iface_block}
d
}" "${TEMPLATE}" > "${rendered_xml}"
mv "${rendered_xml}" "${CYCLONEDDS_XML}"
echo "[dds] 렌더 완료: ${CYCLONEDDS_XML} (loopback + 외부 ${#NICS[@]}개)"

# --- 4. ~/.bashrc env 멱등 주입 (관리 블록으로 통일) ----------------------
# config.sh 는 source 되는 컨텍스트(activate.sh/CI)에만 적용되고, 대화형 셸은
# ~/.bashrc 만 읽으므로 여기에 export 를 심는다. 기존(수동 포함) 관리 라인을 먼저
# 제거하고 마커 블록으로 다시 써 중복을 막는다(멱등).
bashrc="${HOME}/.bashrc"
BEGIN_MARK="# >>> ros2_jazzy_test cyclonedds env >>>"
END_MARK="# <<< ros2_jazzy_test cyclonedds env <<<"
if [[ -f "${bashrc}" ]]; then
    # 이전 관리 블록 제거
    sed -i "/${BEGIN_MARK}/,/${END_MARK}/d" "${bashrc}"
    # 이번 세션에 수동 추가됐을 수 있는 산발적 export/주석 정리
    sed -i \
        -e '/CycloneDDS receive-buffer tuning for large RealSense topics/d' \
        -e '/모든 새 셸 기본 RMW = CycloneDDS/d' \
        -e '\#^export CYCLONEDDS_URI=#d' \
        -e '/^export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp/d' \
        "${bashrc}"
fi
{
    echo "${BEGIN_MARK}"
    echo "# CycloneDDS 표준 + 대용량 토픽 버퍼/인터페이스 튜닝 (dds-tuning.sh 관리, 수동 편집 금지)"
    echo "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp"
    echo "export CYCLONEDDS_URI=\"file://${CYCLONEDDS_XML}\""
    echo "${END_MARK}"
} >> "${bashrc}"
echo "[dds] ~/.bashrc 관리 블록 갱신 (CYCLONEDDS_URI / RMW_IMPLEMENTATION)"

echo "[dds] 완료. 새 터미널 또는 'source ~/.bashrc' 후 cyclonedds 적용."
echo "[dds] 참고: 같은 호스트 통신(호스트↔컨테이너)은 loopback 으로 항상 동작합니다."
echo "[dds]       다른 머신과의 통신은 해당 외부 NIC 가 up 이어야 합니다."
