#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# scripts/dds-probe.sh — DDS 구성별 통신 성립 여부와 대용량 토픽 손실률 측정.
#
# 측정은 머신을 영구 변경하지 않는다. 구성 전환은 환경변수로만 하며 파일도
# sysctl 도 건드리지 않는다 — 그래서 몇 번을 돌려도 결과가 같다.
#
# Usage:
#   eval "$(bash scripts/dds-probe.sh env m1)"   # 이 셸을 m1 구성으로
#   bash scripts/dds-probe.sh talk               # 발행 (머신 A)
#   bash scripts/dds-probe.sh listen             # 수신 + 손실률 (머신 B)
#   bash scripts/dds-probe.sh report             # 인터페이스·소켓 버퍼 관측
#   bash scripts/dds-probe.sh self-check         # 같은 머신 loopback 무결성
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
NODES="${DDS_PROBE_NODES:-${SCRIPT_DIR}/dds_probe_nodes.py}"

# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=resources/config.sh
source "${REPO_ROOT}/resources/config.sh"

# 측정 구성별 환경변수 문장을 stdout 으로. 호출자가 eval 한다.
# 네 구성 모두 RMW 는 CycloneDDS 로 고정 — 비교 대상은 discovery 설정뿐이다.
probe_env() {
    local cfg="${1:-}"
    echo "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp"
    case "${cfg}" in
        m0)
            echo "unset CYCLONEDDS_URI"
            echo "unset ROS_AUTOMATIC_DISCOVERY_RANGE"
            echo "unset ROS_STATIC_PEERS"
            ;;
        m1)
            echo "unset CYCLONEDDS_URI"
            echo "unset ROS_STATIC_PEERS"
            echo "export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET"
            ;;
        m2)
            if [[ -z "${DDS_PROBE_PEERS:-}" ]]; then
                echo "dds-probe: m2 는 DDS_PROBE_PEERS 가 필요하다 (세미콜론 구분, 예: '192.168.1.2;192.168.1.11')" >&2
                exit 2
            fi
            # Validate peer list: valid characters are a-z, A-Z, 0-9, ., :, _, -, with ; separator
            # Pattern: one or more valid chars, optionally followed by (semicolon + valid chars)
            if ! [[ "${DDS_PROBE_PEERS}" =~ ^[a-zA-Z0-9.:_-]+([;][a-zA-Z0-9.:_-]+)*$ ]]; then
                echo "dds-probe: DDS_PROBE_PEERS 에 유효하지 않은 문자가 있거나 빈 세그먼트가 있다" >&2
                exit 2
            fi
            echo "unset CYCLONEDDS_URI"
            echo "export ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST"
            echo "export ROS_STATIC_PEERS=\"${DDS_PROBE_PEERS}\""
            ;;
        m3)
            echo "unset ROS_AUTOMATIC_DISCOVERY_RANGE"
            echo "unset ROS_STATIC_PEERS"
            echo "export CYCLONEDDS_URI=\"file://${CYCLONEDDS_XML}\""
            ;;
        *)
            echo "dds-probe: 알 수 없는 구성 '${cfg}' (m0|m1|m2|m3)" >&2
            exit 2
            ;;
    esac
}

# ROS 오버레이가 source 되어 있지 않으면 어떤 측정도 의미가 없다.
_require_ros() {
    if [[ -z "${AMENT_PREFIX_PATH:-}" ]]; then
        echo "dds-probe: ROS 환경이 없다. 'source /opt/ros/${ROS_DISTRO}/setup.bash' 후 다시 실행하라." >&2
        exit 3
    fi
}

probe_talk() {
    _require_ros
    python3 "${NODES}" talk "$@"
}

probe_listen() {
    _require_ros
    # ros2 CLI 데몬은 이전 실행의 그래프를 캐시해 다른 구성의 결과를 보여준다.
    # 측정 전에 반드시 죽인다.
    ros2 daemon stop >/dev/null 2>&1 || true
    python3 "${NODES}" listen "$@"
}

# 같은 머신 loopback 에서 손실 0% 인지 본다.
# mesh 너머에서 0 프레임이 왔을 때 도구가 고장난 것인지 네트워크가 못 넘긴 것인지
# 구분하는 장치다 — 여기서 통과하면 도구는 무죄다.
probe_self_check() {
    _require_ros
    local hz="${DDS_PROBE_SELFCHECK_HZ:-5}"
    local sec="${DDS_PROBE_SELFCHECK_SEC:-8}"
    local line drop

    python3 "${NODES}" talk --hz "${hz}" --width 320 --height 240 >/dev/null 2>&1 &
    local talker=$!
    # shellcheck disable=SC2064
    trap "kill ${talker} 2>/dev/null || true" EXIT

    line="$(python3 "${NODES}" listen --sec "${sec}" | grep '^RESULT ' || true)"
    kill "${talker}" 2>/dev/null || true
    trap - EXIT

    if [[ -z "${line}" ]]; then
        echo "dds-probe: self-check 실패 — 수신 결과가 없다" >&2
        exit 1
    fi
    drop="$(sed -n 's/.*drop_pct=\([0-9.]*\).*/\1/p' <<< "${line}")"
    echo "dds-probe: self-check ${line}"
    if ! [[ "${drop}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "dds-probe: self-check 실패 — drop_pct 값을 해석할 수 없다: ${line}" >&2
        exit 1
    fi
    if ! command -v awk >/dev/null 2>&1; then
        echo "dds-probe: self-check 실패 — awk 가 없어 손실률을 판정할 수 없다" >&2
        exit 1
    fi
    if awk "BEGIN{exit !(${drop} > 1.0)}"; then
        echo "dds-probe: self-check 실패 — loopback 손실률 ${drop}% (기준 1% 이하). 측정 도구부터 고쳐야 한다." >&2
        exit 1
    fi
    echo "dds-probe: self-check 통과 — 도구 정상"
}

# 측정과 함께 기록해야 하는 환경 관측치.
# SPDP 주소 239.255.0.1:7400 은 RTPS 규격 기본값이라 설정 어디에도 안 적힌다 —
# 실제로 어느 NIC 가 그 그룹에 가입했는지는 런타임에서만 보인다.
probe_report() {
    echo "=== SPDP 멀티캐스트 그룹(239.255.0.1)에 가입한 인터페이스 ==="
    ip maddr show | awk '/^[0-9]+:/{ifc=$2} /239\.255\.0\.1/{print ifc}' | sort -u \
        || echo "(가입 없음 — 노드가 떠 있지 않거나 멀티캐스트가 꺼져 있다)"

    echo
    echo "=== 7400 을 듣고 있는 소켓 ==="
    ss -uanp 2>/dev/null | grep ':7400' | head -5 || echo "(없음)"

    echo
    echo "=== DDS 소켓 수신 버퍼 (rb=byte) ==="
    ss -uanm 2>/dev/null | grep -A1 ':74[0-9][0-9]' | grep -o 'rb[0-9]*' | sort -u | head -5 \
        || echo "(측정 불가 — 노드가 떠 있어야 한다)"

    echo
    echo "=== 커널 버퍼 설정 ==="
    echo "rmem_max=$(sysctl -n net.core.rmem_max 2>/dev/null || echo unknown)"
    echo "rmem_default=$(sysctl -n net.core.rmem_default 2>/dev/null || echo unknown)"
}

case "${1:-}" in
    env)        shift; probe_env "${1:-}" ;;
    talk)       shift; probe_talk "$@" ;;
    listen)     shift; probe_listen "$@" ;;
    report)     shift; probe_report ;;
    self-check) shift; probe_self_check ;;
    *)          echo "dds-probe: 사용법은 파일 상단 주석 참조" >&2; exit 2 ;;
esac
