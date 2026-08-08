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

echo "[10] report 는 네 관측 항목을 모두 낸다"
out="$(bash "${PROBE}" report 2>/dev/null || true)"
assert_contains "report NIC 절"       "${out}" "SPDP 멀티캐스트 그룹"
assert_contains "report 소켓 절"      "${out}" "7400"
assert_contains "report 버퍼 절"      "${out}" "수신 버퍼"
assert_contains "report 커널 설정 절" "${out}" "rmem_default="

# 섹션 비어있음 불변식: 섹션 헤더 직후 다른 헤더가 오면 안 된다 (빈 섹션 탐지).
# 공백 줄을 제거하고 === 로 시작하는 두 행이 연속되면 사이에 데이터가 없는 것.
stripped="$(printf '%s\n' "${out}" | grep -v '^[[:space:]]*$')"
prev_line=""
invariant_passed=true
while IFS= read -r line; do
    if [[ "${line}" =~ ^===.*===$ ]]; then
        if [[ -n "${prev_line}" && "${prev_line}" =~ ^===.*===$ ]]; then
            echo "  FAIL 섹션 비어있음 — 헤더 직후 다른 헤더: '${prev_line}' 다음 '${line}'" >&2
            fails=$((fails + 1))
            invariant_passed=false
            break
        fi
    fi
    prev_line="${line}"
done <<< "${stripped}"
if ! (echo "${stripped}" | grep -q '^===.*===$'); then
    echo "  FAIL 섹션 헤더가 없음" >&2
    fails=$((fails + 1))
elif [[ "${invariant_passed}" == "true" ]]; then
    echo "  PASS 섹션 비어있음 불변식 — 모든 헤더 다음에 데이터 있음"
fi

# 측정 노드(자식 프로세스)가 실제로 받은 환경을 그대로 찍는 스텁.
# env 출력은 오퍼레이터의 셸만 바꾼다. 노드는 talk/listen 이 새로 띄우는 별도
# 프로세스이므로, 그 사이에서 환경이 덧칠되면 결과표에는 고른 적 없는 구성의
# 숫자가 들어간다 — 실제로 그런 적이 있어서(모든 구성이 XML 을 물고 측정됨)
# 이 검사를 상시 assertion 으로 남긴다. 다른 스텁들은 노드가 무엇을 상속받는지
# 전혀 보지 않기 때문에 그 사고를 잡지 못했다.
cat > "${ROOT}/stub_env.py" <<'EOF'
#!/usr/bin/env python3
import os

for key in ("CYCLONEDDS_URI", "ROS_AUTOMATIC_DISCOVERY_RANGE",
            "ROS_STATIC_PEERS", "RMW_IMPLEMENTATION"):
    print("NODE_ENV %s=[%s]" % (key, os.environ.get(key, "<unset>")))
EOF

# 오퍼레이터와 똑같은 순서(eval → 별도 프로세스 기동)로 구성을 적용하고,
# 노드가 본 환경을 stdout 으로 돌려준다.
node_env_for() {
    local cfg="$1"
    (
        set -eu
        export DDS_PROBE_PEERS='192.168.1.2;192.168.1.11'
        # 로그인 셸에 이미 URI 가 있는 상태 — m0~m2 는 이 값을 지워야 한다.
        export CYCLONEDDS_URI='file:///pre-existing/from-login-shell.xml'
        eval "$(bash "${PROBE}" env "${cfg}")"
        AMENT_PREFIX_PATH=/fake DDS_PROBE_NODES="${ROOT}/stub_env.py" bash "${PROBE}" talk
    )
}

echo "[11] 측정 노드가 실제로 받는 환경 = 오퍼레이터가 고른 구성"

out="$(node_env_for m0)"
assert_contains "m0 노드 URI unset"    "${out}" "NODE_ENV CYCLONEDDS_URI=[<unset>]"
assert_contains "m0 노드 RANGE unset"  "${out}" "NODE_ENV ROS_AUTOMATIC_DISCOVERY_RANGE=[<unset>]"
assert_contains "m0 노드 peers unset"  "${out}" "NODE_ENV ROS_STATIC_PEERS=[<unset>]"
assert_contains "m0 노드 RMW"          "${out}" "NODE_ENV RMW_IMPLEMENTATION=[rmw_cyclonedds_cpp]"

out="$(node_env_for m1)"
assert_contains "m1 노드 URI unset"    "${out}" "NODE_ENV CYCLONEDDS_URI=[<unset>]"
assert_contains "m1 노드 RANGE"        "${out}" "NODE_ENV ROS_AUTOMATIC_DISCOVERY_RANGE=[SUBNET]"
assert_contains "m1 노드 peers unset"  "${out}" "NODE_ENV ROS_STATIC_PEERS=[<unset>]"

out="$(node_env_for m2)"
assert_contains "m2 노드 URI unset"    "${out}" "NODE_ENV CYCLONEDDS_URI=[<unset>]"
assert_contains "m2 노드 RANGE"        "${out}" "NODE_ENV ROS_AUTOMATIC_DISCOVERY_RANGE=[LOCALHOST]"
assert_contains "m2 노드 peers"        "${out}" "NODE_ENV ROS_STATIC_PEERS=[192.168.1.2;192.168.1.11]"

# m3 만 URI 가 있어야 하고, 그 값은 env 가 낸 문자열과 정확히 같아야 한다.
m3_uri="$(bash "${PROBE}" env m3 | sed -n 's/^export CYCLONEDDS_URI="\(.*\)"$/\1/p')"
out="$(node_env_for m3)"
assert_contains "m3 노드 URI = env 출력값" "${out}" "NODE_ENV CYCLONEDDS_URI=[${m3_uri}]"
assert_contains "m3 노드 RANGE unset"      "${out}" "NODE_ENV ROS_AUTOMATIC_DISCOVERY_RANGE=[<unset>]"
assert_contains "m3 노드 peers unset"      "${out}" "NODE_ENV ROS_STATIC_PEERS=[<unset>]"

if [[ "${fails}" -gt 0 ]]; then
    echo "FAILED: ${fails}건" >&2
    exit 1
fi
echo "test-dds-probe: 전부 통과"
