#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# scripts/measurement-prep.sh — DDS 구성 측정을 돌릴 수 있는 상태인지 점검하고,
# base 설치가 덮지 않는 간극만 메운다.
#
# ROS2 설치는 여기서 하지 않는다 — install.sh 가 하는 일이다. 이 스크립트는
# 그 뒤에 남는 세 가지 간극만 본다:
#   1) CycloneDDS RMW 패키지. install.sh 는 깔지 않는다(app-install.sh 의
#      colcon 단계에만 있고, 그 단계는 cobot2 워크스페이스를 먼저 요구한다).
#   2) 커널 소켓 버퍼와 cyclonedds.xml. hostcfg.sh dds 가 만든다.
#   3) 측정을 오염시키는 것들 — 방화벽, 이미 떠 있는 DDS participant.
#
# 기본은 점검만 한다. 고치려면 --install 을 준다.
#
# Usage:
#   bash scripts/measurement-prep.sh            # 점검만(시스템 무변경)
#   bash scripts/measurement-prep.sh --install  # 빠진 것 설치(확인 후)
#   bash scripts/measurement-prep.sh --help
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=resources/config.sh
source "${REPO_ROOT}/resources/config.sh"

DO_INSTALL=0
missing=0
blocked=0

# 헤더 주석을 그대로 도움말로 쓴다. 줄 번호로 잘라내지 않는 이유는 파일이 한 줄만
# 늘어도 범위가 어긋나 문장 중간부터 출력되기 때문 — 실제로 그렇게 깨진 적이 있다.
# 저작권 블록 다음의 연속된 주석 덩어리를 첫 비주석 줄까지만 찍는다.
usage() {
    awk '
        /^# scripts\// { show = 1 }
        show && !/^#/  { exit }
        show           { sub(/^# ?/, ""); print }
    ' "${BASH_SOURCE[0]}"
}

case "${1:-}" in
    --install) DO_INSTALL=1 ;;
    --help|-h) usage; exit 0 ;;
    "")        ;;
    *)         echo "prep: 알 수 없는 인자 '${1}'" >&2; usage >&2; exit 2 ;;
esac

# 점검 결과는 전부 stdout 으로 낸다. 이건 사람이 위에서 아래로 읽는 보고서라
# 줄 순서가 내용의 일부다 — 경고만 stderr 로 보내면 뒤따르는 설명과 순서가 섞인다.
# stderr 는 마지막 요약(종료 상태를 설명하는 줄)에만 쓴다.
ok()      { echo "  [OK]      $*"; }
gap()     { echo "  [MISSING] $*"; missing=$((missing + 1)); }
warn()    { echo "  [WARN]    $*"; blocked=$((blocked + 1)); }
note()    { echo "            $*"; }

# --- 1. ROS2 ---------------------------------------------------------------
# 없으면 여기서 멈춘다. 설치는 install.sh 의 몫이고, 그걸 대신하지 않는다.
echo "[1/5] ROS2 ${ROS_DISTRO}"
if [[ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
    ok "/opt/ros/${ROS_DISTRO} 설치됨"
else
    gap "/opt/ros/${ROS_DISTRO} 없음"
    note "→ bash install.sh 를 먼저 완료할 것. 이 스크립트는 ROS2 를 설치하지 않는다."
    echo
    echo "prep: ROS2 가 없어 나머지 점검을 건너뛴다." >&2
    exit 1
fi

set +u
# shellcheck disable=SC1090,SC1091
source "/opt/ros/${ROS_DISTRO}/setup.bash"
set -u

if python3 -c "import ros2multicast" 2>/dev/null; then
    ok "ros2 multicast 사용 가능"
else
    gap "ros2multicast 없음 (ros2cli 미설치)"
fi

# --- 2. CycloneDDS RMW -----------------------------------------------------
# install.sh 가 안 깔아 주는 첫 번째 간극.
echo "[2/5] CycloneDDS RMW"
rmw_pkg="ros-${ROS_DISTRO}-rmw-cyclonedds-cpp"
if dpkg -s "${rmw_pkg}" >/dev/null 2>&1; then
    ok "${rmw_pkg} 설치됨"
elif [[ "${DO_INSTALL}" -eq 1 ]]; then
    echo "  설치: ${rmw_pkg}"
    sudo apt-get update
    sudo apt-get install -y "${rmw_pkg}"
    ok "${rmw_pkg} 설치 완료"
else
    gap "${rmw_pkg} 없음 — RMW_IMPLEMENTATION=rmw_cyclonedds_cpp 가 실패한다"
    note "→ --install 또는 sudo apt install -y ${rmw_pkg}"
fi

# --- 3. 커널 버퍼 + cyclonedds.xml -----------------------------------------
# 둘 다 hostcfg.sh dds 의 산출물. 버퍼가 작으면 대용량 토픽 드롭률이
# 구성 차이가 아니라 커널 설정 차이를 재게 된다.
echo "[3/5] DDS 튜닝 (hostcfg.sh dds 산출물)"
rmem="$(sysctl -n net.core.rmem_default 2>/dev/null || echo 0)"
rmem_want=268435456
xml_ok=0
[[ -f "${CYCLONEDDS_XML}" ]] && xml_ok=1

if [[ "${rmem}" -ge "${rmem_want}" && "${xml_ok}" -eq 1 ]]; then
    ok "rmem_default=${rmem}, XML=${CYCLONEDDS_XML}"
elif [[ "${DO_INSTALL}" -eq 1 ]]; then
    echo "  실행: resources/hostcfg.sh dds (sysctl 설치 + XML 렌더 + ~/.bashrc 블록 재작성)"
    bash "${REPO_ROOT}/resources/hostcfg.sh" dds
    ok "hostcfg.sh dds 완료 — 새 터미널 또는 source ~/.bashrc 후 반영"
else
    [[ "${rmem}" -lt "${rmem_want}" ]] && gap "rmem_default=${rmem} (기대 ${rmem_want} 이상)"
    [[ "${xml_ok}" -eq 0 ]] && gap "${CYCLONEDDS_XML} 없음 — 기준선 구성을 잴 수 없다"
    note "→ --install 또는 bash resources/hostcfg.sh dds"
fi

# --- 4. 방화벽 -------------------------------------------------------------
# 여기서 막히면 "mesh 가 멀티캐스트를 안 넘긴다" 와 구분이 안 된다.
# 방화벽 변경은 이 스크립트가 하지 않는다 — 명령만 알려 준다.
echo "[4/5] 방화벽"
if ! systemctl is-active --quiet ufw 2>/dev/null; then
    ok "ufw 비활성 — DDS 포트 차단 없음"
else
    # 규칙을 읽어 자동 판정하지 않는다. ufw 출력에서 "이 규칙이 DDS 를 허용하는가"를
    # 문자열로 맞히려는 시도는 오탐이 쉽고, 틀리면 막힌 걸 열렸다고 보고하게 된다.
    # 측정 결과 전체가 그 판정에 걸리므로 사람에게 넘긴다.
    warn "ufw 활성 — DDS(UDP 7400번대 + multicast 239.255.0.1)가 막혀 있으면"
    note "  '멀티캐스트가 mesh 를 못 넘는다' 와 구분되지 않는다."
    if sudo -n true 2>/dev/null; then
        note "  현재 규칙:"
        sudo -n ufw status 2>/dev/null | sed 's/^/              /' | head -10
    else
        note "  현재 규칙: 확인 불가(sudo 필요) — sudo ufw status verbose"
    fi
    note "  필요 시:  sudo ufw allow from <상대 IP> proto udp"
    note "  방화벽 변경은 이 스크립트가 하지 않는다 — 직접 판단할 것."
fi

# --- 5. 측정을 오염시키는 DDS participant ----------------------------------
echo "[5/5] 이미 떠 있는 DDS participant"
found=0
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    # 네트워크 모드는 docker inspect 에서만 나온다 — docker ps --format 은
    # .HostConfig 를 모르고 조용히 빈 값을 준다(그래서 host 컨테이너를 놓친다).
    while read -r name; do
        [[ -z "${name}" ]] && continue
        mode="$(docker inspect "${name}" --format '{{.HostConfig.NetworkMode}}' 2>/dev/null || true)"
        if [[ "${mode}" == "host" ]]; then
            warn "컨테이너 '${name}' 가 host 네트워크로 실행 중 — 측정 그래프에 섞인다"
            note "  측정 중에는: docker stop ${name}   (끝나면 docker start ${name})"
            found=1
        fi
    done < <(docker ps --format '{{.Names}}' 2>/dev/null || true)
fi

sock_count="$(ss -uan 2>/dev/null | grep -c ':7400' || true)"
if [[ "${sock_count}" -gt 0 ]]; then
    warn "UDP 7400 소켓 ${sock_count}개 — 다른 ROS 노드가 떠 있다"
    note "  ss -uanp | grep :7400 으로 확인 (컨테이너 소켓은 주인이 안 보인다)"
    found=1
fi
[[ "${found}" -eq 0 ]] && ok "간섭 없음"

# --- 요약 ------------------------------------------------------------------
echo
if [[ "${missing}" -gt 0 ]]; then
    echo "prep: 빠진 것 ${missing}건 — --install 로 채우거나 위 안내대로 처리할 것" >&2
    exit 1
fi
if [[ "${blocked}" -gt 0 ]]; then
    echo "prep: 설치는 충족. 경고 ${blocked}건은 사람이 판단할 것(방화벽/간섭 노드)." >&2
    exit 0
fi
echo "prep: 측정 준비 완료. 다음:"
echo "  bash scripts/dds-probe.sh self-check      # 도구 무결성"
echo "  ros2 multicast receive / send             # mesh 도달성 (양방향 각각)"
