#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# resources/config.sh — distro / 버전 핀(version pin)의 단일 진실 소스.
# distro / 버전 문자열 = 여기 한 곳에서만 정의 — 스크립트마다 하드코딩 금지.
# source 전용 라이브러리 — set -euo 를 여기 두지 않는다(호출 진입점이 셸 옵션을 소유).
#
# 사용법(어느 설치 스크립트에서든):
#   source "$(dirname "${BASH_SOURCE[0]}")/config.sh"   # resources/ 안에서
#   source "$(dirname "$0")/resources/config.sh"        # 최상위(install.sh)에서
#
# 이 파일은 직접 실행 안 됨. set -u 아래에서 source 해도 안전.
# 변수별 정책:
#   - distro/OS 핀: 강제 export(`=`). 사용자 셸에 ROS_DISTRO=humble 같은 값이 남아 오염돼 있어도,
#     이 프로젝트는 jazzy 환경이 대상이라 무조건 jazzy 로 설정.
#     다음 distro 마이그레이션 때 = 이 두 줄만 변경(단일 진실 소스).
#   - 경로/버전 변수: `:=` 패턴(환경변수로 덮어쓰기 허용 — 테스트/CI 에서 유용).

# --- distro / OS (강제 설정) -----------------------------------------------
export ROS_DISTRO=jazzy
export UBUNTU_CODENAME=noble

# apt 비대화(non-interactive) 모드 강제. 설치 명령 stdout = 로그로만(콘솔 = 진행률·에러) → 화면에
# 안 보임 → dpkg 설정 파일 질문(conffile prompt) 떠도 응답 불가 → 설치 정지. noninteractive = 그
# 질문 자체 제거.
export DEBIAN_FRONTEND=noninteractive

# 참고: host application Python 책임 분리.
#   - yolo (object_detection): 컨테이너 image 안에만 존재(PyTorch / ultralytics 등).
#   - voice (voice_processing): host 에 직접 설치(voice-host-install.sh — langchain / openai /
#     openwakeword). 마이크가 하드웨어 종속이라 컨테이너 오디오 passthrough 대신 host 실행(ADR-027).
#     noble PEP 668(externally-managed) 회피 = pip --break-system-packages.
# 자동화 host venv 는 두지 않음(2026-05-27 결정 유지). corecode / pick&place 데모용 수동 venv 는
# scripts/venv-demo/LAB.md 참조 — 인스톨러가 관여 안 함(별도 실행 모델).

# --- 레포 소스 트리 루트 ----------------------------------------------
# 이 파일(resources/config.sh)의 부모 디렉토리 = 레포 루트. clone 경로와 무관하게 자기 위치에서
# 계산 → 단일 진실 소스로 export. colcon install 이후엔 bringup launch 가 __file__ 로 레포
# (컨테이너 compose / config.sh)를 못 찾음 → 대신 이 값 참조. 덮어쓰기 허용(`:=`).
: "${ROS2_JAZZY_TEST_REPO:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export ROS2_JAZZY_TEST_REPO

# --- DSR (jazzy 브랜치 활성 확인 2026-05-26) ---------------
: "${DSR_BRANCH:=${ROS_DISTRO}}"
: "${DSR_EMULATOR_VERSION:=3.0.1}"
: "${DSR_WORKSPACE:=${HOME}/cobot_ws}"

# --- 앱 워크스페이스 경로 (통합 cobot_ws 하위) ------------------------------------
# YOLO_WS: yolo_container(od_msg + object_detection) — dev 모드(docker-compose.dev.yml)에서
#   컨테이너 /ws/src 로 bind-mount(live-mount). 별도 src/ 없이 디렉토리 자체가 패키지.
# VOICE_WS: voice_container(voice_processing) — voice 는 host 직접 실행(컨테이너 아님).
#   voice-host-install.sh 가 wakeword 모델(${VOICE_WS}/voice_processing/resource/*.tflite)을 이 경로에서 읽어 검증.
# 두 경로 모두 dsr-project-install.sh 가 빌드하는 host colcon 워크스페이스의 일부 → 별도 복사 단계 없음. 덮어쓰기 허용.
: "${YOLO_WS:=${DSR_WORKSPACE}/src/cobot2/yolo_container}"
: "${VOICE_WS:=${DSR_WORKSPACE}/src/cobot2/voice_container}"

# --- 커널 트랙 (HWE) --------------------------------------------------
# HWE 커널(Ubuntu 하드웨어 지원 커널) meta 를 명시적으로 설치 → 커널 이미지 + headers + modules-extra 가 항상 함께 묶임.
# 이 meta 가 없으면 다른 패키지(예: nvidia 모듈)가 커널 이미지만 끌어오고 modules-extra
# (wifi / 일부 USB 입력 드라이버가 들어 있음)가 빠짐 → 부팅은 되지만 wifi/USB 키보드 상실:
# 반쪽 커널. nvidia 와 librealsense2-dkms 둘 다 이 headers meta 를 통해 커널 업데이트를 따라감.
# 참고: nvidia-driver-install.sh 의 커널 모듈 meta 계산은 KERNEL_META 에서 'linux-' prefix 를 떼는 데
# 의존(linux-generic-hwe-24.04 → generic-hwe-24.04). prefix 형식을 바꾸면
# 거기 module_meta 이름도 함께 검토.
: "${KERNEL_META:=linux-generic-hwe-24.04}"
: "${KERNEL_HEADERS_META:=linux-headers-generic-hwe-24.04}"

# --- NVIDIA 드라이버 -------------------------------------------------------
# 드라이버를 버전 + flavor 로 명시적으로 핀(버전 고정). 예전 `ubuntu-drivers install` 자동 선택은
# 머신/시점마다 다른 드라이버를 골랐고, 그 드라이버가 의존성으로 modules-extra 없는 반쪽 HWE 커널을
# 끌어와 재부팅 시 검은 화면(wifi/USB 입력 상실) 유발. 작업 머신에서 검증된 known-good 구성을
# 결정론적으로 재현하려고 핀.
#   설치 패키지 = nvidia-driver-${NVIDIA_DRIVER_VERSION}${NVIDIA_DRIVER_FLAVOR}
#   FLAVOR = "" (closed, 기본값) 또는 "-open" (open 커널 모듈).
#   closed 를 기본으로: Optimus(하이브리드) 노트북에서 -open + KMS 가 가끔 내장
#   패널 디스플레이를 못 켜서 검은 화면(gdm 세션 실패)이 나므로, 디스플레이가 더 안정적인 closed 로 핀.
#   VERSION 을 비워 두면 nvidia-driver-install.sh 가 ubuntu-drivers 자동 선택으로 폴백
#   (override 용 — 비결정성을 감수).
: "${NVIDIA_DRIVER_VERSION:=595}"
: "${NVIDIA_DRIVER_FLAVOR:=}"
# CUDA major = 12.8 (PyTorch cu128). host 에는 설치 안 함(host colcon 패키지 중 CUDA 소비자가 없음)
# — 이 값을 읽는 유일한 소비자 = 앱 컨테이너(yolo)의 Dockerfile build-arg.
# pip index 는 cu${CUDA_VERSION//./} 형태로 cu128 생성.
# 12.8 선택 이유: Noble apt repo 에 12-4 가 없고 + PyTorch wheel 이 제공되는 버전(cu118/cu126/cu128)이라서.
: "${CUDA_VERSION:=12.8}"

# --- Docker --------------------------------------------------------------
# 빈 문자열 = docker-install.sh 가 noble 용 최신 stable 설치 후 apt-mark hold.
# 설치 시점에 확정된 버전은 docs/COMPATIBILITY.md 에 기록(설치 때 핀하지는 않음).
# 사용자 결정 2026-05-28. system-layer 설치의 어떤 코드도 이 변수 안 읽음.
: "${DOCKER_VERSION_STRING:=}"

# --- state 파일 (재실행 재개, 구조화 포맷 2026-05-27) ----
: "${STATE_DIR:=${HOME}/.ros2_jazzy_test}"
: "${STATE_FILE:=${STATE_DIR}/state}"

# --- 상세 설치 로그 (append-only — 절대 덮어쓰지 않음) ------------------------
# orchestrate.sh 가 각 단계 명령의 stdout+stderr 전체를 여기 append. 기본적으로 콘솔에는
# [n/total] 진행률 + heartbeat(작업 살아있음 신호)만 보이고, 모든 단계 출력과 경고/에러는 콘솔이 아니라 이 파일로 감.
# 레포 루트에 `install_log` 로 존재(git-ignore — 머신별·재생성 가능, torch/colcon 이면
# 수십 MB 까지 커질 수 있음). 재실행으로 재개할수록 계속 커짐; 정책상 절대 truncate/rotate 안 함
# (필요하면 사용자가 직접 정리). LOG_FILE 환경변수로 덮어쓰기 가능(테스트/CI).
# 경로는 이 파일 위치(resources/config.sh) → 레포 루트로 계산 → cwd 와 무관.
: "${LOG_FILE:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install_log}"

# --- apt 키링 (모든 외부 repo 키링을 한 경로로 통일) ----
: "${KEYRING_DIR:=/etc/apt/keyrings}"

# --- ROS2 DDS / RMW (discovery 가 되려면 host ↔ container 사이에서 일치해야 함) -----------
# host 노드와 yolo/voice 컨테이너가 같은 topic/service 를 보려면 RMW 가 일치해야 함
# (Fast-DDS ↔ CycloneDDS 가 섞이면 같은 topic 도 안 보임). 오염된 셸에서도 결정론적이도록
# 표준을 CycloneDDS 로 핀. activate.sh 가 이 값을 host 환경에 로드하고,
# docker-compose 의 두 서비스가 같은 기본값을 참조 → 양쪽이 일치. 덮어쓸 때는 compose 실행 전에 같은 값을 export.
#
# CycloneDDS 를 쓰는 이유: RealSense raw 같은 큰 topic(컬러 프레임 1장 ≈ 2.6MB)을 안정적으로 받으려면
# OS 소켓 버퍼와 DDS 요청 버퍼를 함께 키워야 하는데, CycloneDDS 는
# XML(CYCLONEDDS_URI)로 버퍼/인터페이스를 명시적으로 제어할 수 있어 결정론적 튜닝 가능.
# 커널 버퍼(sysctl)와 XML 버퍼는 한 세트 — dds-tuning.sh 가 둘 다 설치.
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"

# CycloneDDS 설정 XML 경로 + URI. dds-tuning.sh 가 설치 머신의 유선 NIC 를 감지해
# 이 경로로 렌더(머신별 산출물, 레포에 추적 안 함). CycloneDDS 가 아닌 RMW 에서는
# 무시되므로 항상 export 해도 무해. 컨테이너 = compose 가 이 파일을 mount.
# 일부러 STATE_DIR 이 아니라 XDG config 디렉토리 아래 배치: 이건 ROS2 실행마다 읽는 런타임 설정이고,
# STATE_DIR 은 설치 관리용 기록(재개 state / 이미지 tar)을 담음. 둘을 분리해 두면
# 설치 state 디렉토리를 지워도 살아있는 DDS 설정은 삭제 안 됨.
#
# CYCLONEDDS_XML 이 경로의 단일 진실 소스. host(아래 CYCLONEDDS_URI)와
# compose 서비스(volume mount source: `${CYCLONEDDS_XML:-.../.config/cyclonedds/cyclonedds.xml}`)가 모두
# 여기서 파생되므로, host 노드와 컨테이너에 mount 되는 파일이 반드시 같은 파일임이 보장됨.
# 다른 곳을 가리키려면 CYCLONEDDS_XML 을 덮어쓰기 — CYCLONEDDS_URI 만 단독으로 바꾸면 안 됨.
# 그래서 URI 는 강제 파생(`:-` 기본값 없음): 셸에 남아있는 낡은 CYCLONEDDS_URI — 예: 이전 렌더 경로가
# 남긴 오래된 `~/.bashrc` export — 가 현재 CYCLONEDDS_XML 을 이겨선 안 됨. 이기면
# host(URI)와 컨테이너에 mount 된 파일(XML)이 조용히 서로 다른 두 파일로 갈라져 host↔container
# discovery 가 에러 없이 깨짐. `set -a` 없이도 compose 가 보도록 export(맨 `:=` 가 아니라).
export CYCLONEDDS_XML="${CYCLONEDDS_XML:-${XDG_CONFIG_HOME:-${HOME}/.config}/cyclonedds/cyclonedds.xml}"
export CYCLONEDDS_URI="file://${CYCLONEDDS_XML}"

# DDS 가 쓸 NIC override(콤마로 여러 개 허용). 비면 dds-tuning.sh 가 모든 물리 유선 NIC 를 자동 감지
# (wireless/docker/virtual 제외). CI / 특수 네트워크에서만 명시적으로 지정.
: "${DDS_NETIF:=}"

# --- host 이더넷 정적 IP (로봇 장비 LAN) ------------------------------
# install.sh 의 마지막 단계(network_static_ip)가 nmcli 로 유선 NIC 에 이 IP 를 고정.
# 로봇 LAN 구성: .1=OnRobot 그리퍼 / .100=로봇 컨트롤러 / .30=host. 로봇/그리퍼와 통신하려면
# 같은 서브넷에 있어야 함. gateway/DNS 는 설정 안 함 — 인터넷은 wifi 로 나가고, 이 연결이
# 기본 경로(default route)를 잡으면 인터넷이 끊김(never-default). HOST_ETH_NETIF 가 비면 자동 감지.
: "${HOST_ETH_IP:=192.168.1.30}"
: "${HOST_ETH_PREFIX:=24}"
: "${HOST_ETH_NETIF:=}"

# ROS_DOMAIN_ID — 학생이 ~/.bashrc 에 직접 설정(학습 연습); 설치기는 이걸 묻지도, 주입하지도
# 않음. 결정 규칙은 단순: 명시적 env(학생 자신의 `export ROS_DOMAIN_ID=`)
# > 0(ROS2 기본값). config.sh 는 셸의 값을 그대로 통과시키기만 해서, compose 서비스가
# (bringup 이 이 파일을 source 할 때 이 값을 읽음) 대화형 셸이 export 한 것과 같은 값을 보게 함. 어디에도
# 설정 안 하면 host 와 컨테이너 둘 다 0 으로 기본값이 되어 단일 머신에서 여전히 일치.
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"

# --- 진행률 표시 ([n/total] 시각화) ---------------------
# orchestrate.sh 진행률 분모(total)의 최후 폴백.
# **권위 있는 소스는 orchestrate.sh** (STAGE_*_COUNT + install_steps_total) — install.sh 는
# orchestrate.sh 에서 분모를 계산하고, 이 TOTAL_STEPS 는 orchestrate.sh 가 source 안 됐을 때만 폴백으로 쓰임.
# 그러니 단계를 추가할 때는 orchestrate.sh 의 STAGE 상수만 갱신하고, 이 값은 그 합과 맞춰 두기만 하면 됨.
: "${TOTAL_STEPS:=10}"

# --- 자체 점검 ----------------------------------------------------------
#######################################
# 필수 변수가 비어 있지 않은지 확인. 자식 스크립트가 진입 직후 호출해
# 누락된 필수 변수를 즉시 잡아내기 위한 것.
# Globals:
#   ROS_DISTRO, UBUNTU_CODENAME, STATE_FILE, KEYRING_DIR, KERNEL_META,
#   KERNEL_HEADERS_META, DSR_WORKSPACE, RMW_IMPLEMENTATION, CYCLONEDDS_XML (읽기)
# Outputs:
#   비어 있는 변수가 있으면 그 이름을 stderr 로 출력
# Returns:
#   하나라도 비어 있으면 1, 모두 설정돼 있으면 0
#######################################
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
