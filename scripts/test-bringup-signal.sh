#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# scripts/test-bringup-signal.sh — bringup.sh 의 host voice 노드 종료 방식 검증.
#
# `ros2 run` 은 노드를 exec 하지 않고 subprocess 로 띄우며 SIGTERM 핸들러가 없다.
# 그래서 래퍼 PID 만 kill 하면 노드가 orphan 으로 살아남는다(마이크 점유 + 다음 실행과 중복).
# bringup.sh 는 `set -m` 으로 잡을 프로세스 그룹 리더로 만든 뒤 그룹 전체에 신호를 보낸다.
#
# ROS 설치 없이 돌도록, 같은 구조(자식을 Popen 하고 기다리는 래퍼)를 python 스텁으로 흉내낸다.
#
# Usage: bash scripts/test-bringup-signal.sh
set -o pipefail

STUB="$(mktemp)"
trap 'rm -f "${STUB}"' EXIT
cat > "${STUB}" <<'PY'
import subprocess, sys
# `ros2 run` 과 같은 모양: 노드를 자식으로 띄우고 기다린다. SIGTERM 핸들러 없음.
child = subprocess.Popen([sys.executable, "-c", "import time\nwhile True: time.sleep(0.2)"])
child.wait()
PY

#######################################
# 종료 방식 한 가지를 시험하고 자식 생존 여부를 stdout 에 알린다.
# Arguments:
#   $1 - plain(래퍼만 kill) | group(프로세스 그룹 kill)
# Outputs:
#   stdout 에 orphan | clean
# Returns:
#   스텁이 자식을 못 띄우면 2
#######################################
run_trial() {
    local mode="$1" wrapper child
    [[ "${mode}" == group ]] && set -m
    python3 "${STUB}" &
    wrapper=$!
    set +m

    sleep 1
    child="$(pgrep -P "${wrapper}" | head -1)"
    [[ -n "${child}" ]] || { echo "스텁이 자식을 띄우지 못함" >&2; return 2; }

    if [[ "${mode}" == group ]]; then
        kill -TERM -- -"${wrapper}" 2>/dev/null || true
    else
        kill "${wrapper}" 2>/dev/null || true
    fi
    wait "${wrapper}" 2>/dev/null || true
    sleep 1

    if kill -0 "${child}" 2>/dev/null; then
        kill -9 "${child}" 2>/dev/null || true   # 테스트가 orphan 을 남기지 않도록 회수
        echo orphan
    else
        echo clean
    fi
}

fails=0
expect() {
    local name="$1" want="$2" got="$3"
    if [[ "${got}" == "${want}" ]]; then
        echo "  ✓ ${name} → ${got}"
    else
        echo "  ✗ ${name} → ${got} (기대 ${want})"; fails=$(( fails + 1 ))
    fi
}

echo "ros2 run 형태의 래퍼: 래퍼만 kill 하면 노드가 남는가?"
expect "래퍼 PID 만 kill        " orphan "$(run_trial plain)"
expect "프로세스 그룹 전체 kill " clean  "$(run_trial group)"

echo
if [[ ${fails} -eq 0 ]]; then
    echo "test-bringup-signal: PASS (2/2)"
else
    echo "test-bringup-signal: FAIL (${fails}건)" >&2
    exit 1
fi
