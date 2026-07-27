#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/dds-tuning.sh — CycloneDDS 대용량 토픽(large-topic) 튜닝 설치 (install.sh step 13).
#
# 하는 일 (순서 중요 — sysctl 이 cyclonedds 노드 시작보다 먼저 배치 필수):
#   1. 설치 머신의 물리 외부 NIC(네트워크 카드) 를 자동 감지 (유선·무선 모두, docker/가상은 제외, 케이블 연결 여부와 무관).
#   2. /etc/sysctl.d/60-cyclonedds.conf 설치 + 적용 (재부팅해도 유지되는 소켓/조각(fragment) 버퍼).
#   3. cyclonedds.xml.in 템플릿에 loopback + NIC 목록을 채워 넣어 ${CYCLONEDDS_XML} 로 렌더링.
#   4. ~/.bashrc 에 CYCLONEDDS_URI / RMW_IMPLEMENTATION export 를 멱등하게(여러 번 실행해도 결과 동일) 주입.
#
# 인터페이스 정책: loopback(lo) 을 항상 맨 앞에 배치 (같은 호스트 안의 노드끼리는 cyclonedds 가
# loopback → 127.0.0.1 선호 → 외부 IP 로 자기 자신에게 unicast 보내다 실패하는 상황 회피); 물리 외부 NIC 도
# 다른 머신과 통신하는 경로(cross-host) 를 위해 함께 허용 목록에 포함.
#
# 단독 실행: bash resources/dds-tuning.sh (하드웨어가 바뀌면 목록 갱신을 위해 다시 실행).
# 이 스크립트는 순수 설치 본문 — state 관리(run_step) 는 호출자(install.sh) 담당.
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
