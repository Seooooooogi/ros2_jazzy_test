#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# resources/config.sh — distro / 버전 핀(version pin)의 단일 진실 소스. source 전용.
# 여기 한 곳에서만 정의한다 — 스크립트마다 하드코딩하면 다음 distro 로 넘어갈 때 전부 찾아 고쳐야 한다.
#
# 사용법(어느 설치 스크립트에서든):
#   source "$(dirname "${BASH_SOURCE[0]}")/config.sh"   # resources/ 안에서
#   source "$(dirname "$0")/resources/config.sh"        # 최상위(install.sh)에서
#
# distro/OS 핀만 `=` 로 강제 설정한다 — 사용자 셸에 ROS_DISTRO=humble 이 남아 있어도 덮어써야 하기
# 때문. 나머지 경로/버전 변수는 `:=` 라 환경변수로 덮어쓸 수 있다(테스트 / CI).

# --- distro / OS (강제 설정) -----------------------------------------------
export ROS_DISTRO=jazzy
export UBUNTU_CODENAME=noble

# apt 를 비대화 모드로 고정. 설치 출력은 로그로만 가서 화면에 안 보이므로, dpkg 가 설정 파일을
# 바꿀지 묻는 대화창(conffile prompt)이 뜨면 아무도 답할 수 없어 설치가 그대로 멈춘다.
export DEBIAN_FRONTEND=noninteractive

# 앱 Python 이 사는 곳: yolo(PyTorch / ultralytics)는 컨테이너 이미지 안, voice(langchain /
# openwakeword)는 host 의 system Python. 마이크가 하드웨어에 묶여 컨테이너로 오디오를 넘기는 방식이
# 머신마다 깨졌기 때문이다.

# --- 레포 소스 트리 루트 ----------------------------------------------
# 이 파일의 부모 디렉토리 = 레포 루트. clone 경로와 무관하게 자기 위치에서 계산해 export 한다 —
# colcon 으로 설치된 뒤의 bringup launch 는 자기 힘으로 레포(컨테이너 compose / config.sh)를 못 찾는다.
: "${ROS2_JAZZY_TEST_REPO:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export ROS2_JAZZY_TEST_REPO

# --- DSR (Doosan 로봇 드라이버 + 에뮬레이터) ---------------
: "${DSR_BRANCH:=${ROS_DISTRO}}"
: "${DSR_EMULATOR_VERSION:=3.0.1}"
: "${DSR_WORKSPACE:=${HOME}/cobot2_ws}"

# doosan-robot2 는 upstream 이 아니라 ROKEY-SPARK fork 를 쓴다(호환 패치를 얹을 수 있어서).
# 브랜치가 아니라 커밋으로 핀 — 그 fork 에는 우리가 계속 커밋을 얹기 때문에, 브랜치로 받으면
# 설치 시점마다 다른 리비전이 깔려 어느 머신이 무엇으로 빌드됐는지 추적할 수 없다.
: "${DSR_REPO_URL:=https://github.com/ROKEY-SPARK/doosan-robot2_jazzy.git}"
: "${DSR_COMMIT:=31750d68ed2855c780a8169c39aadb0a2cd80e1f}"

# --- M0609 + RG2 통합 bringup ------------------------------------------
# 로봇 드라이버 · 그리퍼 · RealSense 브라켓을 한 URDF / 한 launch 로 올리는 패키지 —
# containers/bringup.sh 의 진입점이 이 launch 다.
# 기본 브랜치(main)가 humble 용이라 반드시 jazzy 브랜치를 받아야 한다.
# M0609_REPO_DIR 이 이미 있으면 clone 을 건너뛰고(개발 중인 작업본 보호) M0609_REF 는 무시된다.
: "${M0609_REPO_URL:=https://github.com/Seooooooogi/M0609_RG2_Integration}"
: "${M0609_REF:=jazzy}"
: "${M0609_REPO_DIR:=${HOME}/M0609_RG2_Integration}"

# OnRobot RG2 그리퍼 ROS2 패키지(description + msgs + Modbus 드라이버). M0609 레포가 추적하지 않는
# 외부 의존이라 따로 가져오고, upstream 이 push 해도 안 흔들리도록 커밋으로 핀.
: "${ONROBOT_REPO_URL:=https://github.com/ABC-iRobotics/onrobot-ros2}"
: "${ONROBOT_COMMIT:=c6e390313e831a2e54a0ad5894b2911cc360a16a}"

# --- 앱 워크스페이스 경로 (통합 cobot2_ws 하위) ------------------------------------
# YOLO_WS  = yolo 컨테이너가 개발 모드에서 /ws/src 로 bind-mount 하는 패키지 디렉토리.
# VOICE_WS = host 에서 그대로 실행되는 voice_processing 패키지. wakeword 모델(.tflite)이 그 아래
#   resource/ 에 있고, app-install.sh 의 voice 단계가 이 경로에서 모델을 읽어 검증한다.
# 둘 다 host colcon 워크스페이스 안이라 따로 복사하는 단계가 없다.
: "${YOLO_WS:=${DSR_WORKSPACE}/src/cobot2/yolo_container}"
: "${VOICE_WS:=${DSR_WORKSPACE}/src/cobot2/voice_processing}"

# --- 커널 트랙 (HWE) --------------------------------------------------
# HWE(Hardware Enablement) 커널 = Ubuntu LTS 에 최신 하드웨어 지원을 얹은 커널 트랙. meta 패키지로
# 설치해야 커널 이미지 + headers + modules-extra 가 한 묶음으로 따라온다. modules-extra 가 빠지면
# 부팅은 되는데 wifi / 일부 USB 입력이 죽는 반쪽 커널이 된다.
# base-install.sh 의 nvidia 단계가 KERNEL_META 에서 'linux-' 를 떼어 커널 모듈 meta 이름을 만든다 —
# 이름 형식을 바꾸면 그쪽도 함께 본다.
: "${KERNEL_META:=linux-generic-hwe-24.04}"
: "${KERNEL_HEADERS_META:=linux-headers-generic-hwe-24.04}"

# --- NVIDIA 드라이버 -------------------------------------------------------
# 설치 패키지 = nvidia-driver-${VERSION}${FLAVOR}. 자동 선택(ubuntu-drivers)은 머신마다 다른 걸
# 골라 재부팅 후 검은 화면이 난 적 있어 검증된 버전으로 고정한다. 비워 두면 자동 선택으로 돌아간다.
# FLAVOR: "" = closed(기본, 노트북 내장 패널에서 더 안정적), "-open" = open 커널 모듈.
: "${NVIDIA_DRIVER_VERSION:=595}"
: "${NVIDIA_DRIVER_FLAVOR:=}"
# CUDA 버전 — host 에는 설치하지 않는다(host colcon 패키지 중 쓰는 게 없다). 이 값을 읽는 곳은
# yolo 컨테이너 Dockerfile 의 build-arg 뿐이고, 거기서 PyTorch pip index 이름 cu128 을 만든다.
# 12.8 인 이유: noble apt 에 12.4 가 없고, PyTorch wheel 이 실제로 제공되는 버전이라서.
: "${CUDA_VERSION:=12.8}"

# --- Docker --------------------------------------------------------------
# 빈 문자열 = base-install.sh 의 docker 단계가 noble 용 최신 stable 을 깔고 apt-mark hold 로 고정.
# 지금은 어떤 코드도 이 값을 읽지 않는다 — 버전을 직접 지정하고 싶을 때를 위한 자리.
: "${DOCKER_VERSION_STRING:=}"

# --- state 파일 (설치가 끊긴 지점부터 이어서 진행) ----
: "${STATE_DIR:=${HOME}/.ros2_jazzy_test}"
: "${STATE_FILE:=${STATE_DIR}/state}"

# --- 상세 설치 로그 (append-only — 절대 덮어쓰지 않음) ------------------------
# 각 단계 명령의 stdout+stderr 전체가 여기 쌓인다 — 콘솔에는 [n/total] 진행률만 보이므로, 경고와
# 에러를 확인할 곳은 이 파일뿐이다. 레포 루트의 `install_log`(git 추적 안 함, 수십 MB 까지 커질 수
# 있음). 잘라내거나 회전시키지 않는다. 경로는 이 파일 위치에서 계산해 cwd 와 무관하다.
: "${LOG_FILE:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install_log}"

# --- apt 키링 (모든 외부 repo 키링을 한 경로로 통일) ----
# 키링 = apt 가 저장소 서명을 검증할 때 쓰는 공개키 모음.
: "${KEYRING_DIR:=/etc/apt/keyrings}"

# --- ROS2 DDS / RMW -----------
# RMW = ROS2 노드가 통신에 쓰는 미들웨어 구현. host 노드와 컨테이너가 서로를 찾으려면(DDS discovery
# — 같은 망의 노드끼리 자동으로 서로를 발견하는 절차) 양쪽 RMW 가 같아야 한다. Fast-DDS 와
# CycloneDDS 가 섞이면 같은 topic 도 서로 안 보인다.
# CycloneDDS 를 고른 이유: RealSense 컬러 프레임(장당 약 2.6MB) 같은 큰 topic 을 놓치지 않으려면
# 소켓 버퍼를 키워야 하는데, XML 로 버퍼와 인터페이스를 명시 제어할 수 있는 쪽이 CycloneDDS 다.
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"

# CycloneDDS 설정 XML 의 경로. hostcfg.sh 의 dds 단계가 머신마다 이 경로로 렌더하고, host 노드와
# 컨테이너 mount 가 모두 이 한 값에서 파생돼 같은 파일을 본다. 그래서 URI 는 XML 에서 강제로
# 파생시킨다 — 셸에 남은 낡은 CYCLONEDDS_URI 가 이기면 양쪽이 조용히 다른 파일을 보게 되어
# discovery 가 에러 한 줄 없이 깨진다.
# 설치 state 디렉토리를 지워도 살아남도록 STATE_DIR 이 아니라 XDG config 아래 둔다.
export CYCLONEDDS_XML="${CYCLONEDDS_XML:-${XDG_CONFIG_HOME:-${HOME}/.config}/cyclonedds/cyclonedds.xml}"
export CYCLONEDDS_URI="file://${CYCLONEDDS_XML}"

# DDS 가 쓸 NIC 지정(콤마로 여러 개). 비우면 loopback 만 쓴다 — 다른 머신의 ROS2 노드와 토픽을
# 나눠야 하는 드문 경우에만 지정한다.
: "${DDS_NETIF:=}"

# --- host 이더넷 정적 IP (로봇 장비 LAN) ------------------------------
# install.sh 의 마지막 단계가 nmcli 로 유선 NIC 에 이 IP 를 고정한다.
# 로봇 LAN 구성은 .1 = OnRobot 그리퍼 / .100 = 로봇 컨트롤러 / .30 = host — 통신하려면 같은
# 서브넷이어야 한다. gateway/DNS 는 비운다: 인터넷은 wifi 로 나가는데 이 연결이 기본 경로를 잡으면
# 인터넷이 끊긴다. HOST_ETH_NETIF 가 비면 유선 NIC 를 자동으로 찾는다.
: "${HOST_ETH_IP:=192.168.1.30}"
: "${HOST_ETH_PREFIX:=24}"
: "${HOST_ETH_NETIF:=}"

# ROS_DOMAIN_ID 는 설치기가 묻지도 주입하지도 않는다 — 학생이 자기 ~/.bashrc 에 직접 export 하는
# 연습 과제라, 여기서는 셸의 값을 그대로 통과시키기만 한다(그래야 host 와 컨테이너가 같은 값을 본다).
# 아무 데도 설정하지 않으면 양쪽 다 ROS2 기본값 0 이 되어 한 머신 안에서는 여전히 서로 매칭된다.
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"

# --- 진행률 표시 ([n/total]) ---------------------
# 진행률 분모의 폴백. 권위 있는 값은 lib.sh 의 install_steps_total() 이고 이 값은 lib.sh 가
# source 되지 않았을 때만 쓰인다 — 단계를 추가하면 lib.sh 의 STAGE 상수를 고치고 이 값을 그 합에 맞춘다.
: "${TOTAL_STEPS:=9}"

# --- 자체 점검 ----------------------------------------------------------
# 필수 변수가 비어 있지 않은지 확인한다 — 각 설치 스크립트가 진입 직후 불러 누락을 즉시 잡는다.
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
