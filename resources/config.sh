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

# NOTE: host venv 는 폐기 (2026-05-27 결정). application Python 패키지
# (PyTorch / ultralytics / langchain / openai 등) 는 모두 별도(yolo/voice) 컨테이너 안에만 존재.
# host 는 system Python (apt) + colcon 워크스페이스만 책임.

# --- 레포 소스 트리 루트 ------------------------------------------------
# 이 파일(resources/config.sh)의 부모 = 레포 루트. 클론 위치에 무관하게 자기 위치에서 계산해
# 단일 진실 소스로 export 한다. bringup launch 가 colcon install 후 __file__ 로 레포(컨테이너
# compose / config.sh)를 못 찾으므로 이 값을 참조한다. override 허용(`:=`).
: "${ROS2_JAZZY_TEST_REPO:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export ROS2_JAZZY_TEST_REPO

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

# --- Phase 4 이미지 배포 (공개 구글 드라이브에서 받아 docker load) ----------
# 클린설치(install.sh step14)는 이미지를 빌드하지 않고 아래 공개 드라이브 file ID 로 tar 를
# 받아 load 한다(빠른 재현). 직접 빌드/검증(이미지 제작 머신)은 containers/build-all.sh.
#
# file ID = 공개 링크 식별자(secret 아님) — 업로드 후 채운다. 비우면 fetch 가 명확히 실패.
# SHA256 = `docker save` tar 의 무결성 해시. 반드시 레포(여기)에 핀하고 드라이브엔 tar 만 올린다
# — 해시를 tar 와 같은 출처에서 받으면 둘 다 변조 시 검증이 무의미하기 때문(신뢰 출처=레포).
: "${YOLO_IMAGE_GDRIVE_ID:=1pbWlfFb3d5L6E_S5XrN9_7s_OLsg_YvC}"
: "${VOICE_IMAGE_GDRIVE_ID:=1iKKLyreAawlDVBcFKqXlyNCG0JNnogYp}"
: "${YOLO_IMAGE_SHA256:=4b29263968bbd0b0247d8b71a11660b309ea596d6796bd899ef8d9bb6bf5d73b}"
: "${VOICE_IMAGE_SHA256:=092b8138e14b7568d7dbaeb27c875867b2a16083f4ee6a0c9b2c1658bb9c2d0b}"

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

# --- ROS2 DDS / RMW (host ↔ 컨테이너 동일해야 discovery 성립) -----------
# host 노드와 yolo/voice 컨테이너가 같은 topic/service 를 보려면 RMW 가 일치해야 한다
# (Fast-DDS ↔ CycloneDDS 혼합 시 같은 topic 도 안 보임). CycloneDDS 로 표준 핀해
# 오염된 셸에서도 결정적. activate.sh 가 이 값을 host 환경에 싣고, docker-compose 의
# 두 서비스도 같은 기본값을 참조 → 양쪽 일치. override 시엔 compose 실행 전 동일 값 export 할 것.
#
# CycloneDDS 채택 이유: RealSense raw 같은 대용량 토픽(color 1프레임 ≈ 2.6MB)을
# 안정 수신하려면 OS 소켓 버퍼와 DDS 요청 버퍼를 함께 키워야 하는데, CycloneDDS 는
# XML(CYCLONEDDS_URI)로 버퍼/인터페이스를 명시 제어할 수 있어 결정적 튜닝이 가능하다.
# 커널 버퍼(sysctl)와 XML 버퍼는 세트 — dds-tuning.sh 가 둘 다 설치한다.
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"

# CycloneDDS 설정 XML 경로 + URI. dds-tuning.sh 가 설치 머신의 유선 NIC 를 탐지해
# 이 경로에 렌더한다(머신 종속 산출물이라 레포 추적 안 함). 비-CycloneDDS RMW 에선
# 무시되므로 항상 export 해도 무해. 컨테이너는 compose 가 이 파일을 mount 한다.
: "${CYCLONEDDS_XML:=${STATE_DIR}/cyclonedds.xml}"
export CYCLONEDDS_URI="${CYCLONEDDS_URI:-file://${CYCLONEDDS_XML}}"

# DDS 가 사용할 NIC override (콤마구분 허용). 비우면 dds-tuning.sh 가 물리 유선 NIC 를
# 전부 자동 탐지(무선/docker/가상 제외). CI / 특수망에서만 명시 지정.
: "${DDS_NETIF:=}"

# --- host ethernet 고정 IP (로봇 장비 LAN) ------------------------------
# install.sh 마지막 step(network_static_ip)이 nmcli 로 유선 NIC 에 이 IP 를 고정한다.
# 로봇 LAN 구성: .1=OnRobot 그리퍼 / .100=로봇 컨트롤러 / .30=host. 로봇·그리퍼와 같은
# 서브넷이어야 통신 가능. 게이트웨이/DNS 는 두지 않는다 — 인터넷은 wifi 로 나가며, 이
# 연결이 기본 경로를 잡으면 인터넷이 끊긴다(never-default). HOST_ETH_NETIF 비우면 자동 탐지.
: "${HOST_ETH_IP:=192.168.1.30}"
: "${HOST_ETH_PREFIX:=24}"
: "${HOST_ETH_NETIF:=}"

# ROS_DOMAIN_ID 단일 진실 소스. host(activate.sh)와 compose 두 서비스가 같은 값을
# 봐야 discovery 성립. 미설정 셸에서도 결정적이도록 명시 핀.
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-42}"

# --- Progress 표시 ([n/total] 시각화) ---------------------
# 통합 진입점 install.sh 의 전체 단계 수 (a01:6 + a02:4 + a03:1 + a04:1 + dds-tuning:1
# + nvidia-container-toolkit:1 + container-fetch:1 + network-static-ip:1).
# install.sh 의 STEPS_TOTAL 과 일치해야 한다(run-step.sh 의 fallback 으로도 쓰임). 단계 추가 시 함께 갱신.
: "${TOTAL_STEPS:=16}"

# --- Self-check ----------------------------------------------------------
# 자식 스크립트가 진입 직후 호출하면 필수 변수 누락 즉시 catch.
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
