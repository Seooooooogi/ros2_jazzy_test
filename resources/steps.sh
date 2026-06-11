#!/usr/bin/env bash
# shellcheck shell=bash
# resources/steps.sh — install step 정의 단일 소스 (install.sh 전체 / a0N 스테이지-로컬 공유).
# source 전용 라이브러리 — set -euo 를 여기 두지 않는다(호출 진입점이 셸 옵션을 소유).
#
# 선행 source 필요: config.sh, state.sh, run-step.sh. 호출자가 RESOURCE_DIR 를 설정한다.
#
# 번호 규칙: 각 스테이지 함수는 offset 을 받아 run_step 번호 = offset + 로컬k 로 계산한다.
#   install.sh: run_stage_a01 0 → (reboot=step6, install.sh 인라인) → run_stage_a02 6
#               → run_stage_a03 10 → run_stage_a04 11 → step 13-16(install 전용, install.sh 인라인).
#   단독 a0N : offset 0 (스테이지-로컬 [k/N]).
# state key(name)는 offset/번호와 무관 — resume 호환에 영향 없음(같은 name 이면 skip 동일).
#
# reboot(step6)는 본 라이브러리에 두지 않는다: install.sh 와 a01 의 reboot wrapper 가
# 메시지/UNATTENDED 분기/exit-vs-continue 까지 달라, 공유 시 동작이 미묘하게 바뀐다.
# 각 진입점이 reboot 를 인라인으로 소유한다(behavior-preserving 우선).

# 스테이지별 step 수 (reboot 제외). 단계 추가 시 여기 한 곳만 갱신하면
# install.sh 전체 분모와 a0N 스테이지-로컬 분모가 함께 따라온다.
STAGE_A01_COUNT=5
STAGE_A02_COUNT=4
STAGE_A03_COUNT=1
STAGE_A04_COUNT=1
INSTALL_EXTRA_COUNT=4   # install 전용: dds(13) / toolkit(14) / container(15) / network(16)

# install.sh 전체 분모: a01 5 + reboot 1 + a02 4 + a03 1 + a04 1 + extra 4 = 16.
install_steps_total() {
    echo $(( STAGE_A01_COUNT + 1 + STAGE_A02_COUNT + STAGE_A03_COUNT \
             + STAGE_A04_COUNT + INSTALL_EXTRA_COUNT ))
}

# a01: 커널 베이스라인 → NVIDIA → Docker → ROS2 desktop → ROS2 extras (reboot 은 호출자 인라인).
run_stage_a01() {
    local off="$1"
    run_step $((off + 1)) a01_kernel_baseline bash "${RESOURCE_DIR}/kernel-baseline.sh"
    run_step $((off + 2)) a01_nvidia_driver   bash "${RESOURCE_DIR}/nvidia-driver-install.sh"
    run_step $((off + 3)) a01_docker          bash "${RESOURCE_DIR}/docker-install.sh"
    run_step $((off + 4)) a01_ros2_desktop    bash "${RESOURCE_DIR}/ros2-desktop-main.sh"
    run_step $((off + 5)) a01_ros2_extras     bash "${RESOURCE_DIR}/ros2-install.sh"
}

# a02: Doosan DSR → RealSense SDK → RealSense ROS 래퍼 → colcon 빌드.
run_stage_a02() {
    local off="$1"
    run_step $((off + 1)) a02_dsr_project    bash "${RESOURCE_DIR}/dsr-project-install.sh"
    run_step $((off + 2)) a02_realsense_sdk  bash "${RESOURCE_DIR}/realsense-sdk-install.sh"
    run_step $((off + 3)) a02_realsense_ros  bash "${RESOURCE_DIR}/realsense-ros-install.sh"
    run_step $((off + 4)) a02_colcon_build   bash "${RESOURCE_DIR}/colcon-build.sh"
}

# a03: VS Code.
run_stage_a03() {
    local off="$1"
    run_step $((off + 1)) a03_vscode bash "${RESOURCE_DIR}/vscode-install.sh"
}

# a04: 음성 사전 점검(.env). 사용자 입력을 받으므로 --interactive (heartbeat 억제).
run_stage_a04() {
    local off="$1"
    run_step --interactive $((off + 1)) a04_voice_env bash "${RESOURCE_DIR}/voice-env-check.sh"
}
