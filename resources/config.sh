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

# apt 비대화 모드 강제. run-step.sh 가 설치 명령의 stdout 을 로그파일로만 보내므로
# (콘솔엔 진행률 + stderr 만) dpkg 의 conffile/대화 프롬프트가 stdout 으로 나가면
# 화면에 안 보인 채 입력을 기다려 설치가 멈춘다. noninteractive 로 그 경로를 차단.
export DEBIAN_FRONTEND=noninteractive

# --- Host Python venv (application-shell 브랜치) -------------------------
# 본 브랜치는 컨테이너 없이 host 단독 실행(monolith) variant 다. cobot2_ws 의 host 실행
# 패키지(robot_control / pick_and_place_* / voice_processing 등)가 런타임에 import 하는
# application Python(torch / ultralytics / openwakeword / langchain / openai / pymodbus 등)을
# host 에 직접 설치한다. noble 의 PEP 668(externally-managed) 회피를 위해 system Python 전역
# pip 대신 venv(--system-site-packages, rclpy/colcon 가시)를 쓴다. host-python-deps.sh 가 소유.
# (컨테이너 variant 인 application-containers 브랜치는 이 변수를 쓰지 않고 host 설치를 최소화한다.)
: "${HOST_VENV:=${DSR_WORKSPACE}/.venv}"

# --- DSR (jazzy 브랜치 활성 확인 완료 2026-05-26) ---------------
: "${DSR_BRANCH:=${ROS_DISTRO}}"
: "${DSR_EMULATOR_VERSION:=3.0.1}"
: "${DSR_WORKSPACE:=${HOME}/cobot2_ws}"

# --- Kernel track (HWE) --------------------------------------------------
# HWE 커널 메타를 명시 설치해 커널 이미지 + 헤더 + modules-extra 를 항상 함께 보장한다.
# 이 메타가 빠지면 다른 패키지(예: nvidia 모듈)가 커널 이미지만 끌어와 modules-extra
# (wifi / 일부 USB 입력 드라이버 수록) 가 누락 → 부팅은 되나 wifi·USB 키보드가 사라지는
# 반쪽 커널이 된다. nvidia / librealsense2-dkms 모두 이 헤더 메타로 커널 업데이트를 추적.
# 주의: nvidia-driver-install.sh 의 커널-모듈 메타 계산이 KERNEL_META 의 'linux-' 접두사
# 제거에 의존한다 (linux-generic-hwe-24.04 → generic-hwe-24.04). 접두사 형식을 바꾸면
# 그쪽 module_meta 명명도 함께 점검할 것.
: "${KERNEL_META:=linux-generic-hwe-24.04}"
: "${KERNEL_HEADERS_META:=linux-headers-generic-hwe-24.04}"

# --- NVIDIA driver -------------------------------------------------------
# 드라이버를 버전 + 변형으로 명시 핀 고정한다. 과거 `ubuntu-drivers install` 자동선택은
# 머신/시점마다 다른 드라이버를 골랐고, 그 드라이버가 modules-extra 없는 반쪽 HWE 커널을
# 의존성으로 끌어와 재부팅 시 검은 화면(wifi/USB 입력 소실)으로 이어졌다. 작업 머신의
# 검증된 known-good 구성을 결정적으로 재현하기 위해 핀.
#   설치 패키지 = nvidia-driver-${NVIDIA_DRIVER_VERSION}${NVIDIA_DRIVER_FLAVOR}
#   FLAVOR = "" (closed, 기본) 또는 "-open" (오픈 커널 모듈).
#   closed 를 기본으로: Optimus(하이브리드) 노트북에서 -open + KMS 가 내장 패널 디스플레이를
#   못 올려 검은 화면(gdm 세션 실패)이 나는 사례가 있어, 디스플레이가 더 안정적인 closed 로 핀.
#   VERSION 을 빈값으로 두면 nvidia-driver-install.sh 가 ubuntu-drivers 자동선택으로
#   폴백한다 (override 용 — 비결정성 감수).
: "${NVIDIA_DRIVER_VERSION:=595}"
: "${NVIDIA_DRIVER_FLAVOR:=}"
# CUDA 메이저 = 12.8 (PyTorch cu128). host 에는 설치하지 않는다 (host 콜콘 패키지에
# CUDA 소비자 없음) — 이 값을 읽는 유일한 소비자는 Phase 4 yolo 컨테이너 Dockerfile 의
# build-arg 다. pip index 는 cu${CUDA_VERSION//./} 로 cu128 을 구성.
# Noble apt repo 에 12-4 부재 + PyTorch wheel 가용성 (cu118/cu126/cu128) 으로 12.8 선택.
: "${CUDA_VERSION:=12.8}"

# --- Docker --------------------------------------------------------------
# 빈 문자열 = docker-install.sh 가 noble 용 latest stable 설치 후 apt-mark hold.
# 설치 시점에 해소된 버전은 docs/COMPATIBILITY.md 에 기록 (설치 시 핀하지 않음).
# 사용자 결정 2026-05-28. 시스템 레이어 설치에서 이 변수를 읽는 코드는 없음.
: "${DOCKER_VERSION_STRING:=}"

# --- State file (resumable 재실행, 구조화 포맷 2026-05-27) ----
: "${STATE_DIR:=${HOME}/.ros2_jazzy_test}"
: "${STATE_FILE:=${STATE_DIR}/state}"

# --- 설치 상세 로그 (append-only — 덮어쓰기 금지) ------------------------
# run-step.sh 가 각 step 명령의 stdout+stderr 전량을 여기에 append 한다.
# 콘솔에는 [n/total] 진행률과 stderr(경고/에러)만 남고, 대량 출력(apt/pip/colcon)은
# 이 파일로 빠진다. torch/colcon 으로 회당 수십 MB 누적 가능 — resumable 재실행이라
# 계속 쌓이지만 규칙상 truncate/회전하지 않는다 (필요 시 사용자가 수동 정리).
: "${LOG_FILE:=${STATE_DIR}/install.log}"

# --- apt keyring (모든 외부 repo 키링을 한 경로로 통일) ----
: "${KEYRING_DIR:=/etc/apt/keyrings}"

# --- Progress 표시 ([n/total] 시각화) ---------------------
# 통합 진입점 install.sh 의 전체 단계 수 (a01:6 + a02:5 + a03:1 + a04:1).
# a02 에 host-python-deps(host venv 설치) 단계가 추가되어 12 → 13 (application-shell variant).
# run-step.sh 의 STEPS_TOTAL fallback 으로도 쓰인다. 단계 추가 시 함께 갱신.
: "${TOTAL_STEPS:=13}"

# --- Self-check ----------------------------------------------------------
# 자식 스크립트가 진입 직후 호출하면 필수 변수 누락 즉시 catch.
config_assert_set() {
    local var missing=0
    for var in ROS_DISTRO UBUNTU_CODENAME STATE_FILE KEYRING_DIR KERNEL_META KERNEL_HEADERS_META DSR_WORKSPACE; do
        if [[ -z "${!var:-}" ]]; then
            echo "config: required variable '$var' is empty" >&2
            missing=1
        fi
    done
    return "$missing"
}
