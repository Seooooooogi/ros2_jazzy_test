#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# scripts/test-dds-probe.sh — dds-probe.sh env 출력 검증.
#
# env 출력은 그대로 eval 되어 측정 셸의 환경이 된다. 한 줄이라도 어긋나면
# 측정 결과 전체가 다른 구성의 것이 되므로, 출력 문자열을 정확히 고정한다.
#
# Usage: bash scripts/test-dds-probe.sh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROBE="${SCRIPT_DIR}/dds-probe.sh"
fails=0

assert_contains() {
    local label="$1" haystack="$2" needle="$3"
    if [[ "${haystack}" == *"${needle}"* ]]; then
        echo "  PASS ${label}"
    else
        echo "  FAIL ${label} — '${needle}' 없음" >&2
        fails=$((fails + 1))
    fi
}

assert_absent() {
    local label="$1" haystack="$2" needle="$3"
    if [[ "${haystack}" != *"${needle}"* ]]; then
        echo "  PASS ${label}"
    else
        echo "  FAIL ${label} — '${needle}' 가 있으면 안 된다" >&2
        fails=$((fails + 1))
    fi
}

echo "[1] m0 = RMW 만, discovery 변수는 unset"
out="$(bash "${PROBE}" env m0)"
assert_contains "m0 RMW"        "${out}" "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp"
assert_contains "m0 URI unset"  "${out}" "unset CYCLONEDDS_URI"
assert_contains "m0 RANGE unset" "${out}" "unset ROS_AUTOMATIC_DISCOVERY_RANGE"
assert_absent   "m0 RANGE 미설정" "${out}" "export ROS_AUTOMATIC_DISCOVERY_RANGE"

echo "[2] m1 = SUBNET"
out="$(bash "${PROBE}" env m1)"
assert_contains "m1 RANGE"      "${out}" "export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET"
assert_absent   "m1 peers 없음"  "${out}" "export ROS_STATIC_PEERS"
assert_contains "m1 URI unset"  "${out}" "unset CYCLONEDDS_URI"

echo "[3] m2 = LOCALHOST + peers (세미콜론 구분)"
out="$(DDS_PROBE_PEERS='192.168.1.2;192.168.1.11' bash "${PROBE}" env m2)"
assert_contains "m2 RANGE"      "${out}" "export ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST"
assert_contains "m2 peers"      "${out}" 'export ROS_STATIC_PEERS="192.168.1.2;192.168.1.11"'

echo "[4] m2 는 peers 없이 실패해야 한다"
if DDS_PROBE_PEERS='' bash "${PROBE}" env m2 >/dev/null 2>&1; then
    echo "  FAIL peers 없는 m2 가 성공했다" >&2
    fails=$((fails + 1))
else
    echo "  PASS peers 없는 m2 는 실패"
fi

echo "[5] m3 = 현행 XML"
out="$(bash "${PROBE}" env m3)"
assert_contains "m3 URI"        "${out}" "export CYCLONEDDS_URI=\"file://"
assert_contains "m3 RANGE unset" "${out}" "unset ROS_AUTOMATIC_DISCOVERY_RANGE"

echo "[6] 알 수 없는 구성은 종료 코드 2"
bash "${PROBE}" env m9 >/dev/null 2>&1 && rc=0 || rc=$?
if [[ "${rc}" -eq 2 ]]; then echo "  PASS 종료 코드 2"; else
    echo "  FAIL 종료 코드가 ${rc} (기대 2)" >&2; fails=$((fails + 1)); fi

if [[ "${fails}" -gt 0 ]]; then
    echo "FAILED: ${fails}건" >&2
    exit 1
fi
echo "test-dds-probe: 전부 통과"
