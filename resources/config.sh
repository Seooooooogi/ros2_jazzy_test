#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# resources/config.sh · source 전용
#   distro / 버전 핀(version pin)의 단일 진실 소스
#   대입 방식 = distro/OS 핀과 RMW 구현 핀은 `=` 강제 설정 / 나머지는 `:=` 로 환경변수 override 가능

# --- distro / OS (강제 설정) -----------------------------------------------
export ROS_DISTRO=jazzy
export UBUNTU_CODENAME=noble

# apt 비대화 모드 고정
export DEBIAN_FRONTEND=noninteractive

# 앱 Python 위치 = yolo 는 컨테이너 이미지 안 / voice 는 host 의 system Python

# --- 레포 소스 트리 루트 ----------------------------------------------
# 이 파일의 부모 디렉토리 = 레포 루트
: "${COBOT2_INSTALLER_REPO:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export COBOT2_INSTALLER_REPO

# --- DSR (Doosan 로봇 드라이버 + 에뮬레이터) ---------------
: "${DSR_BRANCH:=${ROS_DISTRO}}"
: "${DSR_EMULATOR_VERSION:=3.0.1}"
: "${DSR_WORKSPACE:=${HOME}/cobot2_ws}"

# doosan-robot2 = upstream 아님, ROKEY-SPARK fork
# 핀 대상 = 브랜치 아님, 커밋
: "${DSR_REPO_URL:=https://github.com/ROKEY-SPARK/doosan-robot2_jazzy.git}"
: "${DSR_COMMIT:=31750d68ed2855c780a8169c39aadb0a2cd80e1f}"

# --- M0609 + RG2 통합 bringup ------------------------------------------
# 로봇 드라이버 · 그리퍼 · RealSense 브라켓 = 한 URDF / 한 launch 로 기동하는 패키지
# 기본 브랜치(main) = humble 용 → jazzy 브랜치 필수
: "${M0609_REPO_URL:=https://github.com/ROKEY-SPARK/m0609_rg2_integration}"
: "${M0609_REF:=jazzy}"
: "${M0609_REPO_DIR:=${HOME}/m0609_rg2_integration}"
# 레포 이름이 소문자로 바뀌기 전에 clone 한 머신의 경로. setup-app.sh 의 obtain_m0609 가
# 신규 경로가 아직 없을 때만 1회 옮긴다 — 안 옮기면 같은 레포를 두 벌 받는다.
: "${M0609_REPO_DIR_LEGACY:=${HOME}/M0609_RG2_Integration}"

# OnRobot RG2 그리퍼 ROS2 패키지 = description + msgs + Modbus 드라이버
: "${ONROBOT_REPO_URL:=https://github.com/ABC-iRobotics/onrobot-ros2}"
: "${ONROBOT_COMMIT:=c6e390313e831a2e54a0ad5894b2911cc360a16a}"

# --- 앱 워크스페이스 경로 (통합 cobot2_ws 하위) ------------------------------------
# YOLO_WS  = yolo 컨테이너가 개발 모드에서 /ws/src 로 bind-mount 하는 패키지 디렉토리
# VOICE_WS = host 에서 그대로 실행되는 voice_processing 패키지
: "${YOLO_WS:=${DSR_WORKSPACE}/src/cobot2/yolo_container}"
: "${VOICE_WS:=${DSR_WORKSPACE}/src/cobot2/voice_processing}"

# --- 커널 트랙 (HWE) --------------------------------------------------
# HWE(Hardware Enablement) 커널 = Ubuntu LTS + 최신 하드웨어 지원을 얹은 커널 트랙
: "${KERNEL_META:=linux-generic-hwe-24.04}"
: "${KERNEL_HEADERS_META:=linux-headers-generic-hwe-24.04}"

# --- NVIDIA 드라이버 -------------------------------------------------------
# 설치 패키지 = nvidia-driver-${VERSION}${FLAVOR}
# FLAVOR: "" = closed(기본) / "-open" = open 커널 모듈
: "${NVIDIA_DRIVER_VERSION:=595}"
: "${NVIDIA_DRIVER_FLAVOR:=}"
# CUDA 버전
#   소비처 = yolo 컨테이너 Dockerfile 의 build-arg
: "${CUDA_VERSION:=12.8}"

# --- Docker --------------------------------------------------------------
# 빈 문자열 = base-install.sh 의 docker 단계가 최신 stable 설치 + hold 고정
# 현재 이 값을 읽는 코드 없음
: "${DOCKER_VERSION_STRING:=}"

# --- state 파일 (설치가 끊긴 지점부터 이어서 진행) ----
: "${STATE_DIR:=${HOME}/.cobot2_jazzy_installer}"
: "${STATE_FILE:=${STATE_DIR}/state}"
# 레포 이름이 바뀌기 전에 설치한 머신의 상태 디렉토리. lib.sh 의 state_migrate_legacy 가
# 신규 경로가 아직 없을 때만 1회 옮긴다 — 안 옮기면 완료한 단계를 처음부터 다시 깐다.
: "${STATE_DIR_LEGACY:=${HOME}/.ros2_jazzy_test}"

# --- 상세 설치 로그 (append-only, 덮어쓰기 금지) ------------------------
# 각 단계 명령의 stdout+stderr 전체 = 여기 축적
# 위치 = 레포 루트의 install_log(git 추적 제외)
: "${LOG_FILE:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install_log}"

# --- apt 키링 (모든 외부 repo 키링을 한 경로로 통일) ----
# 키링 = apt 가 저장소 서명 검증에 쓰는 공개키 모음
: "${KEYRING_DIR:=/etc/apt/keyrings}"

# --- ROS2 DDS / RMW -----------
# RMW = ROS2 노드가 통신에 쓰는 미들웨어 구현
# 이 레포의 핀(강제 설정) — 레포 전체의 DDS 측정·튜닝이 CycloneDDS 를 전제하므로
# 머신별 선호로 두지 않는다. 호출 셸에 다른 값이 이미 export 돼 있어도 무시한다.
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

# CycloneDDS 설정 XML 경로
# URI = XML 에서 강제 파생
export CYCLONEDDS_XML="${CYCLONEDDS_XML:-${XDG_CONFIG_HOME:-${HOME}/.config}/cyclonedds/cyclonedds.xml}"
export CYCLONEDDS_URI="file://${CYCLONEDDS_XML}"

# DDS 가 쓸 NIC 지정(콤마로 여러 개)
#   빈 값 = loopback 전용
: "${DDS_NETIF:=}"

# --- host 이더넷 정적 IP (로봇 장비 LAN) ------------------------------
# install.sh 마지막 단계 = nmcli 로 유선 NIC 에 이 IP 고정
# 로봇 LAN 구성
#   .1 = OnRobot 그리퍼 / .100 = 로봇 컨트롤러 / .30 = host
# gateway/DNS = 빈 값(인터넷 경로 = wifi 유지)
# HOST_ETH_NETIF 빈 값 → 유선 NIC 자동 탐지
: "${HOST_ETH_IP:=192.168.1.30}"
: "${HOST_ETH_PREFIX:=24}"
: "${HOST_ETH_NETIF:=}"

# ROS_DOMAIN_ID = 설치기가 질문·주입 모두 안 함
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"

# --- 진행률 표시 ([n/total]) ---------------------
# 진행률 분모의 폴백
#   권위 있는 값 = lib.sh 의 install_steps_total()
: "${TOTAL_STEPS:=9}"

# --- 자체 점검 ----------------------------------------------------------
# 필수 변수 비어 있지 않은지 확인
config_assert_set() {
    local var missing=0
    for var in ROS_DISTRO UBUNTU_CODENAME STATE_FILE KEYRING_DIR KERNEL_META KERNEL_HEADERS_META DSR_WORKSPACE RMW_IMPLEMENTATION CYCLONEDDS_XML; do
        if [[ -z "${!var:-}" ]]; then
            echo "config: required variable '$var' is empty" >&2
            missing=1
        fi
    done
    return "$missing"
}
