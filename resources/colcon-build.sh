#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/colcon-build.sh — cobot2_ws colcon 빌드 (a02 step 4).
#
# DSR + RealSense 설치 후 단일 빌드 (중복 빌드 방지 — DSR/RealSense 자식 스크립트는 빌드 안 함).
# 빌드 범위는 ws src/ 에 symlink 된 패키지로 한정 (dsr-project-install.sh 가 host 패키지만
# symlink → object_detection / voice_processing 등 컨테이너 패키지는 src/ 에 없어 자동 제외).
#   - rosdep init 은 a01 ros2-desktop-main.sh 가 이미 가드 — 여기선 update 만.
#   - --skip-keys=librealsense2: SDK 는 ROS rosdep key 가 아닌 native apt 패키지 (a02 step2).
#   - 증분 빌드 (rm -rf build install log 안 함) — 재개 시 빠름.
# 순수 설치 본문 — state 호출 없음.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

if [[ ! -d "${DSR_WORKSPACE}/src" ]]; then
    echo "colcon-build: ${DSR_WORKSPACE}/src 없음 — DSR 설치 단계 선행 필요" >&2
    exit 1
fi

# ROS2 환경 (set -u 하에서 setup.bash 의 unbound var 회피).
set +u
# shellcheck disable=SC1090,SC1091
source "/opt/ros/${ROS_DISTRO}/setup.bash"
set -u

# CycloneDDS RMW 패키지 보장 — config.sh 가 기본 RMW 를 cyclonedds 로 고정하므로 colcon 이
# 패키지의 기본 RMW 를 해석할 때 rmw_cyclonedds_cpp 가 설치돼 있어야 한다(없으면 dsr_msgs2 등에서
# "Could not find ROS middleware implementation 'rmw_cyclonedds_cpp'" 로 CMake configure 실패).
# ROS desktop 은 fastrtps 만 깔고 cyclonedds 는 별도 패키지라 빌드 선행 조건으로 여기서 설치한다.
# dpkg 가드로 이미 있으면 apt 자체를 건너뜀(멱등 + 재개 시 네트워크 불요).
if ! dpkg -s "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp" >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp"
fi

cd "${DSR_WORKSPACE}"

# rosdep: 워크스페이스 패키지의 선언적 의존 자동 해소 (init 은 a01 에서 완료).
rosdep update
rosdep install --from-paths src --ignore-src --rosdistro "${ROS_DISTRO}" \
    --skip-keys=librealsense2 -y

# colcon 빌드 (src/ 의 패키지 = doosan-robot2 + host 패키지만).
colcon build

echo "colcon-build: success building colcon workspace at ${DSR_WORKSPACE}"
