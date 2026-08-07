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

case "${1:-}" in
    env)  shift; probe_env "${1:-}" ;;
    *)    echo "dds-probe: 사용법은 파일 상단 주석 참조" >&2; exit 2 ;;
esac
