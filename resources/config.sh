#!/usr/bin/env bash
# resources/config.sh — Single source of truth for distro / version pins.
# distro / version 문자열을 스크립트마다 박지 않고 여기 한 곳에서만 정의한다.
#
# Usage (from any installer script):
#   source "$(dirname "${BASH_SOURCE[0]}")/config.sh"   # resources/ 내부에서
#   source "$(dirname "$0")/resources/config.sh"        # top-level (a01-a04 / install.sh)
#
# 본 파일은 직접 실행하지 않는다. set -u 환경에서도 안전하게 source 가능.
# 변수별 정책:
#   - distro/OS 핀: 강제 export (`=`). 사용자 셸이 ROS_DISTRO=humble 로 오염되어 있어도
#     본 프로젝트는 jazzy 환경 구성이 목적이므로 무조건 jazzy 로 set.
#     다음 distro 마이그레이션 시 이 두 줄만 바꾸면 됨 (단일 진실 소스).
#   - 경로/버전 변수: `:=` 패턴 (환경변수 override 허용 — 테스트/CI 에서 유용).

# --- Distro / OS (FORCED) -----------------------------------------------
export ROS_DISTRO=jazzy
export UBUNTU_CODENAME=noble

# NOTE: host venv 는 폐기 (2026-05-27 결정). application Python 패키지
# (PyTorch / ultralytics / langchain / openai 등) 는 모두 별도(yolo/voice) 컨테이너 안에만 존재.
# host 는 system Python (apt) + colcon 워크스페이스만 책임.

# --- DSR (jazzy 브랜치 활성 확인 완료 2026-05-26) ---------------
: "${DSR_BRANCH:=${ROS_DISTRO}}"
: "${DSR_EMULATOR_VERSION:=3.0.1}"
: "${DSR_WORKSPACE:=${HOME}/cobot2_ws}"

# --- NVIDIA / CUDA -------------------------------------------------------
# 빈 문자열 = nvidia-driver-install.sh 가 `ubuntu-drivers install` 로 noble 권장
# 드라이버를 자동 선택 (RTX 4060 에서 ≈580) 후 apt-mark hold. 사용자 결정 2026-05-28.
# 숫자 (예: 580) 를 명시하면 그 버전을 force-pin 설치 (override, CI/특수 GPU 용).
# 하드핀을 기본값으로 두지 않는 이유: 추후 결정할 CUDA 메이저가 요구하는 최소
# 드라이버를 자동으로 만족시키기 위함.
: "${NVIDIA_DRIVER_VERSION:=}"
# 추후 결정 (Noble repo 에 12-4 부재, 12-6/12-8/13-x 가용).
# 빈 문자열 = 미결정. 자식 스크립트가 사용 시 비어 있으면 에러.
: "${CUDA_VERSION:=}"

# --- Docker --------------------------------------------------------------
# 빈 문자열 = docker-install.sh 가 noble 용 latest stable 설치 후 apt-mark hold.
# 설치 시점에 해소된 버전은 docs/COMPATIBILITY.md 에 기록 (설치 시 핀하지 않음).
# 사용자 결정 2026-05-28. 시스템 레이어 설치에서 이 변수를 읽는 코드는 없음.
: "${DOCKER_VERSION_STRING:=}"

# --- State file (resumable 재실행, 구조화 포맷 2026-05-27) ----
: "${STATE_DIR:=${HOME}/.ros2_jazzy_test}"
: "${STATE_FILE:=${STATE_DIR}/state}"

# --- apt keyring (모든 외부 repo 키링을 한 경로로 통일) ----
: "${KEYRING_DIR:=/etc/apt/keyrings}"

# --- Progress 표시 ([n/total] 시각화) ---------------------
# 통합 진입점 install.sh 의 전체 단계 수 (a01:5 + a02:4 + a03:1 + a04:1).
# run-step.sh 의 STEPS_TOTAL fallback 으로도 쓰인다. 단계 추가 시 함께 갱신.
: "${TOTAL_STEPS:=11}"

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
