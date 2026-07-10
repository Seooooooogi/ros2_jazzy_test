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
# host 빌드는 컨테이너 전용 패키지(object_detection — yolo 이미지 안에서만 실행)를 --packages-skip 로
# 건너뛴다. voice_processing 은 host 에서 직접 실행(voice-host-install.sh)하므로 여기서 함께 빌드 —
# console_script 가 system python shebang 을 받아 host 에 깐 langchain/openwakeword 를 본다.
# pick_and_place_* 는 그 안의 COLCON_IGNORE 파일로 skip.
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

# colcon 빌드. object_detection(yolo)은 host 에서 실행 불가(torch 가 yolo 이미지 안에만) → --packages-skip.
# voice_processing 은 host 직접 실행이라 여기서 빌드(voice-host-install.sh 가 langchain/openwakeword 를
# host 에 깔아 둠 → console_script 의 system python 이 그대로 봄). pick_and_place_* 는 COLCON_IGNORE 로 자동 skip.
colcon build --packages-skip object_detection

# wakeword 모델이 설치 트리(install/)에 들어갔는지 확인.
# 런타임의 voice_processing 은 모델을 get_package_share_directory() 로 찾는다 — 소스 트리가 아니다.
# voice-host-install.sh 의 검증 게이트는 이 빌드보다 먼저 돌기 때문에 소스 경로만 볼 수 있다.
# 그래서 setup.py 의 data_files 가 resource/ 를 설치하지 않는 경우를 여기서만 잡을 수 있다.
# 안 잡으면 첫 `ros2 run voice_processing get_keyword` 에서야 드러난다.
voice_share="${DSR_WORKSPACE}/install/voice_processing/share/voice_processing/resource"
if [[ -d "${DSR_WORKSPACE}/install/voice_processing" ]] \
    && ! compgen -G "${voice_share}/*.tflite" >/dev/null; then
    echo "colcon-build: voice_processing 의 wakeword 모델이 설치 트리에 없음" >&2
    echo "           기대 경로: ${voice_share}/*.tflite" >&2
    echo "           voice_processing/setup.py 의 data_files 가 resource/ 를 설치하는지 확인." >&2
    exit 1
fi

echo "colcon-build: success building colcon workspace at ${DSR_WORKSPACE}"
