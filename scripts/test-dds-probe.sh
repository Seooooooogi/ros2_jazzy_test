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
ROOT="$(mktemp -d)"
trap 'rm -rf "${ROOT}"' EXIT
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
DDS_PROBE_PEERS='' bash "${PROBE}" env m2 >/dev/null 2>&1 && rc=0 || rc=$?
if [[ "${rc}" -eq 2 ]]; then echo "  PASS peers 없는 m2 는 실패"; else
    echo "  FAIL 종료 코드가 ${rc} (기대 2)" >&2; fails=$((fails + 1)); fi

echo "[4a] m2 는 peers 에 따옴표가 있으면 실패해야 한다"
DDS_PROBE_PEERS='x";touch' bash "${PROBE}" env m2 >/dev/null 2>&1 && rc=0 || rc=$?
if [[ "${rc}" -eq 2 ]]; then echo "  PASS 따옴표 있는 m2 는 실패"; else
    echo "  FAIL 종료 코드가 ${rc} (기대 2)" >&2; fails=$((fails + 1)); fi

echo "[4b] m2 는 peers 에 공백이 있으면 실패해야 한다"
DDS_PROBE_PEERS='192.168.1.2 192.168.1.11' bash "${PROBE}" env m2 >/dev/null 2>&1 && rc=0 || rc=$?
if [[ "${rc}" -eq 2 ]]; then echo "  PASS 공백 있는 m2 는 실패"; else
    echo "  FAIL 종료 코드가 ${rc} (기대 2)" >&2; fails=$((fails + 1)); fi

echo "[4c] m2 는 peers 에 빈 세그먼트가 있으면 실패해야 한다"
DDS_PROBE_PEERS='192.168.1.2;;192.168.1.11' bash "${PROBE}" env m2 >/dev/null 2>&1 && rc=0 || rc=$?
if [[ "${rc}" -eq 2 ]]; then echo "  PASS 빈 세그먼트 있는 m2 는 실패"; else
    echo "  FAIL 종료 코드가 ${rc} (기대 2)" >&2; fails=$((fails + 1)); fi

echo "[5] m3 = 현행 XML"
out="$(bash "${PROBE}" env m3)"
assert_contains "m3 URI"        "${out}" "export CYCLONEDDS_URI=\"file://"
assert_contains "m3 RANGE unset" "${out}" "unset ROS_AUTOMATIC_DISCOVERY_RANGE"

echo "[6] 알 수 없는 구성은 종료 코드 2"
bash "${PROBE}" env m9 >/dev/null 2>&1 && rc=0 || rc=$?
if [[ "${rc}" -eq 2 ]]; then echo "  PASS 종료 코드 2"; else
    echo "  FAIL 종료 코드가 ${rc} (기대 2)" >&2; fails=$((fails + 1)); fi

echo "[7] self-check 는 ROS 환경이 없으면 안내 후 종료 코드 3"
( unset AMENT_PREFIX_PATH
  bash "${PROBE}" self-check >/dev/null 2>&1 ) && rc=0 || rc=$?
if [[ "${rc}" -eq 3 ]]; then echo "  PASS ROS 미source 시 종료 코드 3"; else
    echo "  FAIL 종료 코드가 ${rc} (기대 3)" >&2; fails=$((fails + 1)); fi

cat > "${ROOT}/stub_bad_drop.py" <<'EOF'
#!/usr/bin/env python3
import sys
import time

mode = sys.argv[1] if len(sys.argv) > 1 else ""
if mode == "talk":
    time.sleep(3600)
elif mode == "listen":
    print("RESULT received=1 expected=1 drop_pct=NaN hz=1.0", flush=True)
EOF

echo "[8] self-check 는 drop_pct 를 숫자로 읽지 못하면 실패해야 한다 (통과 문구 없이)"
out="$(AMENT_PREFIX_PATH=/fake DDS_PROBE_NODES="${ROOT}/stub_bad_drop.py" bash "${PROBE}" self-check 2>&1)" && rc=0 || rc=$?
if [[ "${rc}" -eq 1 && "${out}" != *"통과"* ]]; then
    echo "  PASS drop_pct 해석 불가 시 종료 코드 1, 통과 문구 없음"
else
    echo "  FAIL 종료 코드 ${rc} 또는 통과 문구 포함 — 출력: ${out}" >&2; fails=$((fails + 1))
fi

cat > "${ROOT}/stub_ok.py" <<'EOF'
#!/usr/bin/env python3
import sys
import time

mode = sys.argv[1] if len(sys.argv) > 1 else ""
if mode == "talk":
    time.sleep(3600)
elif mode == "listen":
    print("RESULT received=40 expected=40 drop_pct=0.0 hz=5.0", flush=True)
EOF

echo "[9] self-check 는 손실률이 기준 이하면 통과해야 한다"
out="$(AMENT_PREFIX_PATH=/fake DDS_PROBE_NODES="${ROOT}/stub_ok.py" bash "${PROBE}" self-check 2>&1)" && rc=0 || rc=$?
if [[ "${rc}" -eq 0 && "${out}" == *"통과"* ]]; then
    echo "  PASS 정상 손실률에서 통과"
else
    echo "  FAIL 종료 코드 ${rc} 또는 통과 문구 없음 — 출력: ${out}" >&2; fails=$((fails + 1))
fi

if [[ "${fails}" -gt 0 ]]; then
    echo "FAILED: ${fails}건" >&2
    exit 1
fi
echo "test-dds-probe: 전부 통과"
