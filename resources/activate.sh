#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/activate.sh — 비대화형(non-interactive) 셸에서 ROS2 환경 한 번에 활성화.
# ~/.bashrc 자동 source 미적용 실행(CI / cron / systemd / 스크립트 실행)에서도
# ros2 / colcon / rclpy 바로 쓰도록 환경 변수 확보.
# source 전용 라이브러리 — set -euo 를 여기 두지 않는다(호출 진입점이 셸 옵션을 소유).
#
# 사용법:
#   source "$(dirname "${BASH_SOURCE[0]}")/activate.sh"
#   # 이후 ros2 / colcon / rclpy 사용 가능(system Python).
#
# voice application Python(langchain / openai / openwakeword) = host 직접 설치(voice-host-install.sh) →
# system python 이 그대로 봄(별도 활성화 불요). yolo application Python 은 컨테이너 image 안.
# 이 wrapper 는 ROS2 + 워크스페이스 overlay 를 켜서 host 노드(voice_processing 등)를 인식하게 한다.

_ACT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${_ACT_DIR}/config.sh"

if [[ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
else
    echo "activate: /opt/ros/${ROS_DISTRO}/setup.bash not found — ROS2 ${ROS_DISTRO} not installed?" >&2
fi

# 워크스페이스 overlay(colcon 빌드 후) — `ros2 run voice_processing get_keyword` 등 host 패키지 인식용.
if [[ -f "${DSR_WORKSPACE}/install/setup.bash" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "${DSR_WORKSPACE}/install/setup.bash"
fi
