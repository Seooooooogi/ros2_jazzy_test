#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# a01-prerequirements.sh — host 사전준비 (NVIDIA 드라이버 + Docker + ROS2 jazzy + Gazebo).
#
# 순차 실행 진입점: a01 → reboot → a02 → ... (Quick Ref).
# 본 스크립트가 state 프레이밍을 소유 (step_begin/step_end_*) — 자식 resource 스크립트는
# 순수 설치 본문. M5 install.sh 통합 시에도 state 호출은 한 곳(여기)에만 존재.
# 재실행 안전: 완료 단계는 state 파일 기준 skip (Hard Rule #2/#3).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="${SCRIPT_DIR}/resources"
# shellcheck source=resources/config.sh
source "${RESOURCE_DIR}/config.sh"
# shellcheck source=resources/state.sh
source "${RESOURCE_DIR}/state.sh"
# shellcheck source=resources/confirm.sh
source "${RESOURCE_DIR}/confirm.sh"
config_assert_set

A01_STEPS=5

# run_step <n> <name> <cmd...> — DONE 이면 skip, 아니면 begin → 실행 → ok/fail 마킹.
run_step() {
    local n="$1" name="$2"
    shift 2
    if step_should_skip "${name}"; then
        echo "[${n}/${A01_STEPS}] skip: ${name} (이미 DONE)"
        return 0
    fi
    step_begin "${n}" "${A01_STEPS}" "${name}"
    if "$@"; then
        step_end_ok
    else
        step_end_fail
        exit 1
    fi
}

run_step 1 a01_nvidia_driver bash "${RESOURCE_DIR}/nvidia-driver-install.sh"
run_step 2 a01_docker        bash "${RESOURCE_DIR}/docker-install.sh"
run_step 3 a01_ros2_desktop  bash "${RESOURCE_DIR}/ros2-desktop-main.sh"
run_step 4 a01_ros2_extras   bash "${RESOURCE_DIR}/ros2-install.sh"

# --- step 5: reboot (Hard Rule #9 confirm + 재부팅 루프 방지) -------------
if step_should_skip a01_reboot; then
    echo "a01: 모든 단계 완료 (reboot 포함). 재실행할 작업 없음."
    state_dump
    exit 0
fi
step_begin 5 "${A01_STEPS}" a01_reboot
confirm_or_abort "모든 사전준비 설치 완료. NVIDIA 드라이버 / docker 그룹 적용을 위해 지금 재부팅할까요?"
# 중요: reboot 전에 DONE 을 디스크에 기록 — 재부팅 후 재실행이 이 단계를 건너뛰어
# 무한 reboot 루프를 방지. reboot 자체 실패 시 상태가 낙관적이나, 실패는 시끄럽고
# 수동 재실행으로 회복 가능하므로 루프 회피를 우선.
step_end_ok
echo "a01: 재부팅합니다... (복귀 후 a02 부터 진행)"
sudo reboot
