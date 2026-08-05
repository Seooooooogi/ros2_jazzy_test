#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# resources/config.sh · source 전용
#   distro / 버전 핀(version pin)의 단일 진실 소스
#   정의는 이 파일 한 곳뿐(스크립트마다 하드코딩 → 다음 distro 이관 때 전부 찾아 고쳐야 함)
#
# 사용법(어느 설치 스크립트에서든):
#   source "$(dirname "${BASH_SOURCE[0]}")/config.sh"   # resources/ 안에서
#   source "$(dirname "$0")/resources/config.sh"        # 최상위(install.sh)에서
#
# 대입 방식
#   distro/OS 핀 = `=` 강제 설정(이유: 사용자 셸에 남은 ROS_DISTRO=humble 도 덮어써야 함)
#   나머지 경로/버전 변수 = `:=` → 환경변수 override 가능(테스트 / CI)

# --- distro / OS (강제 설정) -----------------------------------------------
export ROS_DISTRO=jazzy
export UBUNTU_CODENAME=noble

# apt 비대화 모드 고정
#   설치 출력 = 로그행 → 화면에 안 보임
#   dpkg conffile prompt 발생 시 응답 불가 → 설치 정지
export DEBIAN_FRONTEND=noninteractive

# 앱 Python 위치
#   yolo(PyTorch / ultralytics) = 컨테이너 이미지 안
#   voice(langchain / openwakeword) = host 의 system Python
#     이유: 마이크 = 하드웨어 종속 → 컨테이너로 오디오 넘기는 방식이 머신마다 깨짐

# --- 레포 소스 트리 루트 ----------------------------------------------
# 이 파일의 부모 디렉토리 = 레포 루트
#   clone 경로와 무관하게 자기 위치에서 계산 후 export
#   필요 이유: colcon 설치 후의 bringup launch = 레포(컨테이너 compose / config.sh) 자력 탐색 불가
: "${ROS2_JAZZY_TEST_REPO:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export ROS2_JAZZY_TEST_REPO

# --- DSR (Doosan 로봇 드라이버 + 에뮬레이터) ---------------
: "${DSR_BRANCH:=${ROS_DISTRO}}"
: "${DSR_EMULATOR_VERSION:=3.0.1}"
: "${DSR_WORKSPACE:=${HOME}/cobot2_ws}"

# doosan-robot2 = upstream 아님, ROKEY-SPARK fork (fork 이유: 호환 패치를 얹을 수 있음)
# 핀 대상 = 브랜치 아님, 커밋
#   fork 에 커밋이 계속 얹힘 → 브랜치로 받으면 설치 시점마다 다른 리비전
#   → 어느 머신이 무엇으로 빌드됐는지 추적 불가
: "${DSR_REPO_URL:=https://github.com/ROKEY-SPARK/doosan-robot2_jazzy.git}"
: "${DSR_COMMIT:=31750d68ed2855c780a8169c39aadb0a2cd80e1f}"

# --- M0609 + RG2 통합 bringup ------------------------------------------
# 로봇 드라이버 · 그리퍼 · RealSense 브라켓 = 한 URDF / 한 launch 로 기동하는 패키지
#   containers/bringup.sh 의 진입점 = 이 launch
# 기본 브랜치(main) = humble 용 → jazzy 브랜치 필수
# M0609_REPO_DIR 이미 존재 → clone skip(개발 중 작업본 보호) + M0609_REF 무시
: "${M0609_REPO_URL:=https://github.com/Seooooooogi/M0609_RG2_Integration}"
: "${M0609_REF:=jazzy}"
: "${M0609_REPO_DIR:=${HOME}/M0609_RG2_Integration}"

# OnRobot RG2 그리퍼 ROS2 패키지 = description + msgs + Modbus 드라이버
#   M0609 레포가 추적하지 않는 외부 의존 → 별도 취득
#   커밋 핀 → upstream push 에도 설치 결과 불변
: "${ONROBOT_REPO_URL:=https://github.com/ABC-iRobotics/onrobot-ros2}"
: "${ONROBOT_COMMIT:=c6e390313e831a2e54a0ad5894b2911cc360a16a}"

# --- 앱 워크스페이스 경로 (통합 cobot2_ws 하위) ------------------------------------
# YOLO_WS  = yolo 컨테이너가 개발 모드에서 /ws/src 로 bind-mount 하는 패키지 디렉토리
# VOICE_WS = host 에서 그대로 실행되는 voice_processing 패키지
#   wakeword 모델(.tflite) 위치 = 그 아래 resource/
#   app-install.sh 의 voice 단계 = 이 경로에서 모델 읽어 검증
# 둘 다 host colcon 워크스페이스 안 → 별도 복사 단계 없음
: "${YOLO_WS:=${DSR_WORKSPACE}/src/cobot2/yolo_container}"
: "${VOICE_WS:=${DSR_WORKSPACE}/src/cobot2/voice_processing}"

# --- 커널 트랙 (HWE) --------------------------------------------------
# HWE(Hardware Enablement) 커널 = Ubuntu LTS + 최신 하드웨어 지원을 얹은 커널 트랙
# meta 패키지 설치 필수
#   meta = 커널 이미지 + headers + modules-extra 한 묶음
#   modules-extra 누락 → 부팅은 되나 wifi / 일부 USB 입력이 죽는 반쪽 커널
# base-install.sh 의 nvidia 단계 = KERNEL_META 에서 'linux-' 제거 → 커널 모듈 meta 이름 생성 → 이름 형식 변경 시 그쪽도 함께 확인
: "${KERNEL_META:=linux-generic-hwe-24.04}"
: "${KERNEL_HEADERS_META:=linux-headers-generic-hwe-24.04}"

# --- NVIDIA 드라이버 -------------------------------------------------------
# 설치 패키지 = nvidia-driver-${VERSION}${FLAVOR}
# 버전 고정(pin) 이유
#   자동 선택(ubuntu-drivers) = 머신마다 다른 드라이버 선택 → 재부팅 후 검은 화면 사례 발생
#   → 검증된 버전으로 고정
#   빈 값 = 자동 선택으로 폴백
# FLAVOR: "" = closed(기본, 노트북 내장 패널에서 더 안정적) / "-open" = open 커널 모듈
: "${NVIDIA_DRIVER_VERSION:=595}"
: "${NVIDIA_DRIVER_FLAVOR:=}"
# CUDA 버전
#   host 설치 없음(host colcon 패키지 중 사용처 없음)
#   유일한 소비처 = yolo 컨테이너 Dockerfile 의 build-arg → PyTorch pip index 이름 cu128 생성
#   12.8 선택 이유: noble apt 에 12.4 없음 + PyTorch wheel 이 실제 제공되는 버전
: "${CUDA_VERSION:=12.8}"

# --- Docker --------------------------------------------------------------
# 빈 문자열 = base-install.sh 의 docker 단계가 noble 용 최신 stable 설치 + apt-mark hold 고정
# 현재 이 값을 읽는 코드 없음(용도 = 버전 직접 지정용 자리)
: "${DOCKER_VERSION_STRING:=}"

# --- state 파일 (설치가 끊긴 지점부터 이어서 진행) ----
: "${STATE_DIR:=${HOME}/.ros2_jazzy_test}"
: "${STATE_FILE:=${STATE_DIR}/state}"

# --- 상세 설치 로그 (append-only, 덮어쓰기 금지) ------------------------
# 각 단계 명령의 stdout+stderr 전체 = 여기 축적(콘솔 = [n/total] 진행률만 → 경고·에러 확인처 = 이 파일뿐)
# 위치 = 레포 루트의 `install_log`(git 추적 제외, 수십 MB 까지 증가 가능)
# 절단·회전(rotate) 없음
# 경로 = 이 파일 위치에서 계산 → cwd 무관
: "${LOG_FILE:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install_log}"

# --- apt 키링 (모든 외부 repo 키링을 한 경로로 통일) ----
# 키링 = apt 가 저장소 서명 검증에 쓰는 공개키 모음
: "${KEYRING_DIR:=/etc/apt/keyrings}"

# --- ROS2 DDS / RMW -----------
# RMW = ROS2 노드가 통신에 쓰는 미들웨어 구현
# DDS discovery = 같은 망의 노드끼리 자동으로 서로를 발견하는 절차
#   host 노드 ↔ 컨테이너 상호 발견 조건 = 양쪽 RMW 동일
#   Fast-DDS + CycloneDDS 혼합 → 같은 topic 도 상호 비가시
# CycloneDDS 선택 이유
#   RealSense 컬러 프레임(장당 약 2.6MB) 같은 큰 topic 무손실 수신 = 소켓 버퍼 증설 필요
#   버퍼·인터페이스를 XML 로 명시 제어 가능한 쪽 = CycloneDDS
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"

# CycloneDDS 설정 XML 경로
#   hostcfg.sh 의 dds 단계 = 머신마다 이 경로로 렌더
#   host 노드 mount + 컨테이너 mount = 모두 이 한 값에서 파생 → 같은 파일 참조
# URI = XML 에서 강제 파생
#   셸에 남은 낡은 CYCLONEDDS_URI 가 우선 → 양쪽이 조용히 다른 파일 참조
#   → discovery 가 에러 한 줄 없이 깨짐
# 위치 = STATE_DIR 아님, XDG config 아래(이유: 설치 state 디렉토리를 지워도 생존)
export CYCLONEDDS_XML="${CYCLONEDDS_XML:-${XDG_CONFIG_HOME:-${HOME}/.config}/cyclonedds/cyclonedds.xml}"
export CYCLONEDDS_URI="file://${CYCLONEDDS_XML}"

# DDS 가 쓸 NIC 지정(콤마로 여러 개)
#   빈 값 = loopback 전용
#   지정 대상 = 다른 머신의 ROS2 노드와 토픽을 나눠야 하는 드문 경우만
: "${DDS_NETIF:=}"

# --- host 이더넷 정적 IP (로봇 장비 LAN) ------------------------------
# install.sh 마지막 단계 = nmcli 로 유선 NIC 에 이 IP 고정
# 로봇 LAN 구성
#   .1 = OnRobot 그리퍼 / .100 = 로봇 컨트롤러 / .30 = host
#   통신 조건 = 같은 서브넷
# gateway/DNS = 빈 값
#   인터넷 경로 = wifi
#   이 연결이 기본 경로 획득 → 인터넷 단절
# HOST_ETH_NETIF 빈 값 → 유선 NIC 자동 탐지
: "${HOST_ETH_IP:=192.168.1.30}"
: "${HOST_ETH_PREFIX:=24}"
: "${HOST_ETH_NETIF:=}"

# ROS_DOMAIN_ID = 설치기가 질문·주입 모두 안 함
#   학생이 자기 ~/.bashrc 에 직접 export 하는 연습 과제
#   여기 역할 = 셸의 값을 그대로 통과 → host 와 컨테이너가 같은 값 참조
#   어디에도 미설정 → 양쪽 다 ROS2 기본값 0 → 한 머신 안에서는 여전히 상호 매칭
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"

# --- 진행률 표시 ([n/total]) ---------------------
# 진행률 분모의 폴백
#   권위 있는 값 = lib.sh 의 install_steps_total()
#   이 값 사용 시점 = lib.sh 미 source 시에만
#   단계 추가 시 = lib.sh 의 STAGE 상수 수정 + 이 값을 그 합에 맞춤
: "${TOTAL_STEPS:=9}"

# --- 자체 점검 ----------------------------------------------------------
# 필수 변수 비어 있지 않은지 확인(호출 시점 = 각 설치 스크립트 진입 직후 → 누락 즉시 검출)
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
