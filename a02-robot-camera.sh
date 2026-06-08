#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# a02-robot-camera.sh — 로봇/카메라 레이어 (DSR robot + RealSense camera + colcon 빌드).
#
# 순차 실행: a01 → reboot → a02 → ...
# a01 과 동일하게 본 스크립트가 state 프레이밍(run_step)을 소유 — 자식 resource 스크립트는
# 순수 설치 본문. 향후 단일 진입점으로 통합하더라도 state 호출은 오케스트레이터 한 곳에만 둔다.
# CUDA/PyTorch 는 host 에 설치하지 않음: application Python (PyTorch / ultralytics / langchain)
# 은 별도 컨테이너(yolo/voice) 전용이고, host colcon 패키지(robot_control / od_msg / doosan-robot2)
# 중 CUDA 소비자가 없다.
# 재실행 안전: 완료 단계는 state 파일 기준 skip (apt source 중복·재설치 방지).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="${SCRIPT_DIR}/resources"

# root 로 직접 실행 금지 — HOME=/root 가 되어 state / clone / 워크스페이스가 /root 로
# 잘못 들어가 일반 사용자 환경에 반영되지 않는다. 필요한 명령은 스크립트가 sudo 로 호출.
if [[ "$(id -u)" -eq 0 ]]; then
    echo "a02: sudo 로 실행하지 마세요. 일반 사용자로 'bash a02-robot-camera.sh' 실행." >&2
    echo "     (필요한 명령은 스크립트가 알아서 sudo 로 호출합니다.)" >&2
    exit 1
fi

# shellcheck source=resources/config.sh
source "${RESOURCE_DIR}/config.sh"
# shellcheck source=resources/state.sh
source "${RESOURCE_DIR}/state.sh"
config_assert_set

# 단독 실행 시 스테이지-로컬 진행률 ([n/4]). 통합 실행(install.sh)은 자체 STEPS_TOTAL=12 사용.
STEPS_TOTAL=4
# shellcheck source=resources/run-step.sh
source "${RESOURCE_DIR}/run-step.sh"

run_step 1 a02_dsr_project    bash "${RESOURCE_DIR}/dsr-project-install.sh"
run_step 2 a02_realsense_sdk  bash "${RESOURCE_DIR}/realsense-sdk-install.sh"
run_step 3 a02_realsense_ros  bash "${RESOURCE_DIR}/realsense-ros-install.sh"
run_step 4 a02_colcon_build   bash "${RESOURCE_DIR}/colcon-build.sh"

state_dump
echo "a02: 완료 — DSR + RealSense 설치 및 ${DSR_WORKSPACE} 빌드 (CUDA/PyTorch 는 별도 컨테이너)"
