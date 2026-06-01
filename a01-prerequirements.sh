#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# a01-prerequirements.sh — host 사전준비 (NVIDIA 드라이버 + Docker + ROS2 jazzy + Gazebo).
#
# 순차 실행 진입점: a01 → reboot → a02 → ... (Quick Ref).
# 본 스크립트가 state 프레이밍을 소유 (step_begin/step_end_*) — 자식 resource 스크립트는
# 순수 설치 본문. 향후 단일 진입점으로 통합하더라도 state 호출은 오케스트레이터 한 곳에만 둔다.
# 재실행 안전: 완료 단계는 state 파일 기준 skip (apt source 중복·재설치 방지).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="${SCRIPT_DIR}/resources"

# root 로 직접 실행 금지 — 스크립트가 필요한 곳에서 내부적으로 sudo 를 호출한다.
# `sudo bash a01...` 로 통째 실행하면 HOME=/root 가 되어 state / docker 그룹 / ~/.bashrc
# 가 전부 /root 로 잘못 들어가 일반 사용자 환경에 반영되지 않는다.
if [[ "$(id -u)" -eq 0 ]]; then
    echo "a01: sudo 로 실행하지 마세요. 일반 사용자로 'bash a01-prerequirements.sh' 실행." >&2
    echo "     (필요한 명령은 스크립트가 알아서 sudo 로 호출합니다.)" >&2
    exit 1
fi

# shellcheck source=resources/config.sh
source "${RESOURCE_DIR}/config.sh"
# shellcheck source=resources/state.sh
source "${RESOURCE_DIR}/state.sh"
# shellcheck source=resources/confirm.sh
source "${RESOURCE_DIR}/confirm.sh"
config_assert_set

# 단독 실행 시 스테이지-로컬 진행률 ([n/6]). 통합 실행(install.sh)은 자체 STEPS_TOTAL=12 사용.
STEPS_TOTAL=6
# shellcheck source=resources/run-step.sh
source "${RESOURCE_DIR}/run-step.sh"

# kernel-baseline 을 nvidia 보다 먼저: HWE 커널 메타 + 헤더 + modules-extra 보장이
# nvidia 모듈 반쪽-커널 brick 과 DKMS 헤더 누락을 둘 다 차단하는 전제다.
run_step 1 a01_kernel_baseline bash "${RESOURCE_DIR}/kernel-baseline.sh"
run_step 2 a01_nvidia_driver   bash "${RESOURCE_DIR}/nvidia-driver-install.sh"
run_step 3 a01_docker          bash "${RESOURCE_DIR}/docker-install.sh"
run_step 4 a01_ros2_desktop    bash "${RESOURCE_DIR}/ros2-desktop-main.sh"
run_step 5 a01_ros2_extras     bash "${RESOURCE_DIR}/ros2-install.sh"

# --- step 6: reboot (되돌릴 수 없는 작업이라 사용자 confirm + 재부팅 루프 방지) ---
if step_should_skip a01_reboot; then
    echo "a01: 모든 단계 완료 (reboot 포함). 재실행할 작업 없음."
    state_dump
    exit 0
fi
step_begin 6 "${STEPS_TOTAL}" a01_reboot
confirm_or_abort "모든 사전준비 설치 완료. NVIDIA 드라이버 / docker 그룹 적용을 위해 지금 재부팅할까요?"
# 중요: reboot 전에 DONE 을 디스크에 기록 — 재부팅 후 재실행이 이 단계를 건너뛰어
# 무한 reboot 루프를 방지. reboot 자체 실패 시 상태가 낙관적이나, 실패는 시끄럽고
# 수동 재실행으로 회복 가능하므로 루프 회피를 우선.
step_end_ok
echo "a01: 재부팅합니다... (복귀 후 a02 부터 진행)"
sudo reboot
