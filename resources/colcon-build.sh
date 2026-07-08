#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/colcon-build.sh — cobot_ws 워크스페이스 colcon 빌드 (a02 의 step 4).
#
# DSR + RealSense 설치 후 딱 한 번만 빌드 (중복 빌드 방지 — DSR/RealSense 하위 스크립트는 빌드 안 함).
# 하나로 합쳐진 워크스페이스의 src/ (dsr-project-install.sh 가 레포에서 복사해 둠) 안에 모든 패키지 묶임.
# host 빌드는 컨테이너 전용 패키지(object_detection / voice_processing — 각자 이미지 안에서만 실행)를
# --packages-skip 로 건너뛰고, pick_and_place_* 는 그 안의 COLCON_IGNORE 파일로 skip.
#   - rosdep init 은 a01 의 ros2-desktop-main.sh 에서 이미 처리 → 여기선 update 만.
#   - --skip-keys=librealsense2: 이 SDK 는 apt 로 까는 네이티브 패키지 → ROS rosdep 키 아님 (a02 step2).
#   - 증분(incremental) 빌드 — build/install/log 를 rm -rf 안 함 → 재개(resume) 시 빠름.
# 순수 설치 본문 — state 함수 호출 안 함.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

if [[ ! -d "${DSR_WORKSPACE}/src" ]]; then
    echo "colcon-build: ${DSR_WORKSPACE}/src missing — the DSR install step must run first" >&2
    exit 1
fi

# ROS2 환경 로드 (set -u 상태에서 setup.bash 가 미정의 변수(unbound var)로 터지는 문제 회피).
set +u
# shellcheck disable=SC1090,SC1091
source "/opt/ros/${ROS_DISTRO}/setup.bash"
set -u

# CycloneDDS RMW(ROS 미들웨어 구현) 패키지 반드시 깔아 둠 — config.sh 가 기본 RMW 를 cyclonedds 로 핀(고정)해
# 둠 → colcon 이 패키지의 기본 RMW 를 찾을 때 rmw_cyclonedds_cpp 설치돼 있어야 함 (없으면 dsr_msgs2 등이
# CMake configure 단계에서 "Could not find ROS middleware implementation 'rmw_cyclonedds_cpp'" 로 실패).
# ROS desktop 은 fastrtps 만 깔고 cyclonedds 는 별도 패키지 → 빌드 전제 조건으로 여기서 설치.
# 이미 깔려 있으면 dpkg 로 확인해 apt 를 통째로 건너뜀 (멱등 + 재개 시 네트워크 불필요).
if ! dpkg -s "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp" >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp"
fi

cd "${DSR_WORKSPACE}"

# rosdep: 워크스페이스 패키지들이 선언해 둔 의존성을 자동 설치 (init 은 a01 에서 이미 끝냄).
rosdep update
rosdep install --from-paths src --ignore-src --rosdistro "${ROS_DISTRO}" \
    --skip-keys=librealsense2 -y

# colcon 빌드. 합쳐진 워크스페이스 src 에는 이제 컨테이너 패키지(object_detection / voice_processing)도 포함
# (컨테이너 dev bind-mount 용). 하지만 host 에서는 이들을 실행 불가 — torch / openwakeword 가 yolo/voice
# 이미지 안에만 있기 때문. 그래서 host 빌드가 host 범위를 벗어나지 않도록 건너뜀 (ament_python 이라 "빌드"
# 자체는 문제없이 되지만, 실행 못 하는 노드를 host 에 깔면 오해 유발). pick_and_place_* 는 COLCON_IGNORE 로 자동 skip.
colcon build --packages-skip object_detection voice_processing

echo "colcon-build: success building colcon workspace at ${DSR_WORKSPACE}"
