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

# application-shell: host venv 가 있으면 활성화한 뒤 빌드한다. ament_python 패키지의 entry_point
# console_script shebang 은 setup.py 를 실행하는 python(=활성 venv python)으로 박히므로, 이렇게 빌드하면
# `ros2 run <pkg> <node>` 가 venv 의 application Python(torch/openwakeword 등)을 보게 된다. venv 없으면
# (application-containers variant) no-op — system python 으로 빌드.
if [[ -n "${HOST_VENV:-}" && -d "${HOST_VENV}" ]]; then
    set +u
    # shellcheck disable=SC1091
    source "${HOST_VENV}/bin/activate"
    set -u
fi

cd "${DSR_WORKSPACE}"

# rosdep: 워크스페이스 패키지의 선언적 의존 자동 해소 (init 은 a01 에서 완료).
rosdep update
rosdep install --from-paths src --ignore-src --rosdistro "${ROS_DISTRO}" \
    --skip-keys=librealsense2 -y

# colcon 빌드 (src/ 의 패키지 = doosan-robot2 + host 패키지만).
colcon build

echo "success building colcon workspace at ${DSR_WORKSPACE}"
