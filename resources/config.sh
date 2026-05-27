#!/usr/bin/env bash
# resources/config.sh — Single source of truth for distro / version pins.
# Hard Rule #1: distro / version 문자열을 스크립트마다 박지 않는다.
#
# Usage (from any installer script):
#   source "$(dirname "${BASH_SOURCE[0]}")/config.sh"   # resources/ 내부에서
#   source "$(dirname "$0")/resources/config.sh"        # top-level (a01-a06 / install.sh)
#
# 본 파일은 직접 실행하지 않는다. set -u 환경에서도 안전하게 source 가능.
# 변수별 정책:
#   - distro/OS 핀: 강제 export (`=`). 사용자 셸이 ROS_DISTRO=humble 로 오염되어 있어도
#     본 프로젝트는 jazzy 환경 구성이 목적이므로 무조건 jazzy 로 set.
#     다음 distro 마이그레이션 시 이 두 줄만 바꾸면 됨 (Hard Rule #1 단일 진실 소스).
#   - 경로/버전 변수: `:=` 패턴 (환경변수 override 허용 — 테스트/CI 에서 유용).

# --- Distro / OS (FORCED) -----------------------------------------------
export ROS_DISTRO=jazzy
export UBUNTU_CODENAME=noble

# NOTE: host venv 는 ADR-008 (2026-05-27) 에 따라 폐기. application Python 패키지
# (PyTorch / ultralytics / langchain / openai 등) 는 모두 Phase 4 컨테이너 안에만 존재.
# host 는 system Python (apt) + colcon 워크스페이스만 책임.

# --- DSR (ADR-003: jazzy 브랜치 활성 확인 완료 2026-05-26) ---------------
: "${DSR_BRANCH:=${ROS_DISTRO}}"
: "${DSR_EMULATOR_VERSION:=3.0.1}"
: "${DSR_WORKSPACE:=${HOME}/cobot_ws}"

# --- NVIDIA / CUDA -------------------------------------------------------
# M2 진입 시 ubuntu-drivers devices 결과 따라 확정. 현재는 humble 의 570 placeholder.
: "${NVIDIA_DRIVER_VERSION:=570}"
# M3 진입 전 ADR-006 으로 결정 (Noble repo 에 12-4 부재, 12-6/12-8/13-x 가용).
# 빈 문자열 = 미결정. 자식 스크립트가 사용 시 비어 있으면 에러.
: "${CUDA_VERSION:=}"

# --- Docker (M2 진입 시 apt-cache madison docker-ce 로 확정) ------------
: "${DOCKER_VERSION_STRING:=}"

# --- State file (Hard Rule #3: resumable, 구조화 포맷 ADR 2026-05-27) ----
: "${STATE_DIR:=${HOME}/.ros2_jazzy_test}"
: "${STATE_FILE:=${STATE_DIR}/state}"

# --- apt keyring (Hard Rule #7: 모든 외부 repo 키링을 한 경로로 통일) ----
: "${KEYRING_DIR:=/etc/apt/keyrings}"

# --- Progress 표시 (Hard Rule #4: [n/total] 시각화) ---------------------
: "${TOTAL_STEPS:=6}"   # M5 install.sh 통합 시 a01..a06 총 6 단계

# --- Self-check ----------------------------------------------------------
# 자식 스크립트가 진입 직후 호출하면 필수 변수 누락 즉시 catch.
config_assert_set() {
    local var missing=0
    for var in ROS_DISTRO UBUNTU_CODENAME STATE_FILE KEYRING_DIR; do
        if [[ -z "${!var:-}" ]]; then
            echo "config: required variable '$var' is empty" >&2
            missing=1
        fi
    done
    return "$missing"
}
