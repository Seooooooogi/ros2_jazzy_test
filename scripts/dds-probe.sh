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
#
# listen 의 마지막 줄:
#   RESULT received=<개> expected=<개> drop_pct=<%> hz=<Hz>
#
#   drop_pct 는 백분율(%)이다 — 0.5 는 0.5% 이지 50% 가 아니다. 결과표와 판정
#   기준도 같은 단위로 읽는다: 통과 = 기준선 구성 대비 +1 퍼센트포인트(%p) 이내.
#   self-check 의 통과선 1.0 역시 1% 를 뜻한다. 이 단위를 분수로 오해하면
#   100배 차이로 판정이 뒤집혀 다른 구성이 채택된다.
#
# 환경변수:
#   DDS_PROBE_PEERS          m2 구성이 요구하는 상대 주소 목록. 세미콜론 구분
#                            (예: '192.168.1.2;192.168.1.11'). 콤마·공백 불가.
#   DDS_PROBE_NODES          발행/수신 노드 파이썬 파일 경로.
#                            기본값 = 이 스크립트 옆의 dds_probe_nodes.py
#   DDS_PROBE_SELFCHECK_HZ   self-check 발행 주기(Hz). 기본 5
#   DDS_PROBE_SELFCHECK_SEC  self-check 수신 시간(초). 기본 8
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
NODES="${DDS_PROBE_NODES:-${SCRIPT_DIR}/dds_probe_nodes.py}"

# config.sh 를 이 셸에 그대로 source 하지 않는다.
#
# config.sh 는 설치기용 파일이라 CYCLONEDDS_URI 를 무조건 export 한다. 이 스크립트가
# 그것을 상속하면, 오퍼레이터가 `eval "$(... env m0)"` 로 URI 를 지워 놓아도 talk/
# listen/self-check 이 띄우는 노드는 다시 XML 을 물고 뜬다 — DDS 설정 단계를 마친
# 머신에서는 XML 이 실제로 있으므로 조용히 읽히고, XML 없이 도는지 보려던 세 구성이
# 전부 XML 과 함께 측정된다. 결과표는 한 구성을 네 번 잰 숫자로 채워지고, 아무도
# 측정하지 않은 구성이 채택된다. 컨테이너 안에서 노드를 직접 실행하는 경로는
# config.sh 를 아예 거치지 않으므로 host 쪽과 다른 것을 재게 된다.
#
# 그래서 필요한 두 값만 서브셸에서 뽑아 온다. 이 프로세스의 환경은 호출 셸 그대로
# 유지되고, 노드가 보는 구성 = 오퍼레이터가 고른 구성이 된다.
_probe_config_get() {
    (
        # shellcheck source-path=SCRIPTDIR/..
        # shellcheck source=resources/config.sh
        source "${REPO_ROOT}/resources/config.sh" >/dev/null 2>&1
        printf '%s\n' "${!1-}"
    )
}
PROBE_CYCLONEDDS_XML="$(_probe_config_get CYCLONEDDS_XML)"
PROBE_ROS_DISTRO="$(_probe_config_get ROS_DISTRO)"

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
            echo "export CYCLONEDDS_URI=\"file://${PROBE_CYCLONEDDS_XML}\""
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
        echo "dds-probe: ROS 환경이 없다. 'source /opt/ros/${PROBE_ROS_DISTRO}/setup.bash' 후 다시 실행하라." >&2
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
    local nics sockets buffers rmem_max rmem_default

    echo "=== SPDP 멀티캐스트 그룹(239.255.0.1)에 가입한 인터페이스 ==="
    nics="$(ip maddr show | awk '/^[0-9]+:/{ifc=$2} $2=="239.255.0.1"{print ifc}' | sort -u)"
    if [[ -n "${nics}" ]]; then
        printf '%s\n' "${nics}"
    else
        echo "(가입 없음 — 노드가 떠 있지 않거나 멀티캐스트가 꺼져 있다)"
    fi

    echo
    echo "=== 7400 을 듣고 있는 소켓 ==="
    sockets="$(ss -uanp 2>/dev/null | grep ':7400' | head -5 || true)"
    if [[ -n "${sockets}" ]]; then
        printf '%s\n' "${sockets}"
    else
        echo "(없음)"
    fi

    echo
    echo "=== DDS 소켓 수신 버퍼 (rb=byte) ==="
    buffers="$(ss -uanm 2>/dev/null | grep -A1 ':74[0-9][0-9]' | grep -o 'rb[0-9]*' | sort -u | head -5 || true)"
    if [[ -n "${buffers}" ]]; then
        printf '%s\n' "${buffers}"
    else
        echo "(측정 불가 — 노드가 떠 있어야 한다)"
    fi

    echo
    echo "=== 커널 버퍼 설정 ==="
    rmem_max="$(sysctl -n net.core.rmem_max 2>/dev/null || echo unknown)"
    rmem_default="$(sysctl -n net.core.rmem_default 2>/dev/null || echo unknown)"
    echo "rmem_max=${rmem_max}"
    echo "rmem_default=${rmem_default}"
}

case "${1:-}" in
    env)        shift; probe_env "${1:-}" ;;
    talk)       shift; probe_talk "$@" ;;
    listen)     shift; probe_listen "$@" ;;
    report)     shift; probe_report ;;
    self-check) shift; probe_self_check ;;
    *)          echo "dds-probe: 사용법은 파일 상단 주석 참조" >&2; exit 2 ;;
esac
