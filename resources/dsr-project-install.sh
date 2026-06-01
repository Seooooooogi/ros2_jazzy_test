#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/dsr-project-install.sh — Doosan DSR(doosan-robot2) clone + 의존성 + 에뮬레이터 (a02 step 1).
#
# backup/dsr-project-install{,_25}.sh 의 jazzy 마이그레이션 + idempotency.
#   - clone 브랜치 -b ${DSR_BRANCH}(=jazzy). 이미 받은 경우 skip (재현성 — git pull 안 함).
#   - 워크스페이스 = ${DSR_WORKSPACE}(=~/cobot2_ws). 본 브랜치(application-shell)는 컨테이너 없이
#     host 단독 실행(monolith) variant 이므로 cobot2_ws 의 host 실행 패키지를 모두 src/ 로 복사한다.
#     런타임 application Python(torch / ultralytics / openwakeword / langchain 등)은 host venv
#     (host-python-deps.sh)가 제공. (컨테이너 variant 인 application-containers 브랜치는 robot_control /
#     od_msg 만 복사하고 나머지는 yolo/voice 컨테이너가 담당.)
#     복사(symlink 아님): 워크스페이스가 레포 위치에 의존하지 않게 — 탈착식 미디어(USB)에서
#     실행해도 빼면 깨지지 않는다. 레포가 소스 진실원본이라 재실행 시 레포 기준 재동기화.
#   - 에뮬레이터: doosanrobot/dsr_emulator:${DSR_EMULATOR_VERSION} 명시 태그 pull.
#     태그를 config.sh 단일 소스로 통제 (apt/docker latest drift 차단). upstream
#     install_emulator.sh 도 동일 pull 만 수행하므로, 호출 대신 직접 pull.
#   - rosdep update / colcon build 는 a02 colcon-build.sh 가 담당 (중복 빌드 방지).
# 순수 설치 본문 — state 호출 없음 (a02 오케스트레이터가 step 프레이밍 소유).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"          # 레포 루트 (resources/ 의 부모)
WS_SRC="${DSR_WORKSPACE}/src"
DSR_REPO_URL="https://github.com/doosan-robotics/doosan-robot2.git"

# host colcon 빌드 대상 패키지. application-shell variant = host 단독 실행이므로 전체 포함.
# (application-containers variant 는 robot_control od_msg 만 — 나머지는 컨테이너.)
HOST_PKGS=(robot_control od_msg pick_and_place_text pick_and_place_voice rokey voice_processing object_detection)

# 1) 워크스페이스 src 디렉토리.
mkdir -p "${WS_SRC}"

# 2) doosan-robot2 clone (idempotent — .git 있으면 skip).
if [[ -d "${WS_SRC}/doosan-robot2/.git" ]]; then
    echo "dsr: doosan-robot2 이미 clone 됨 (skip)"
else
    git clone -b "${DSR_BRANCH}" "${DSR_REPO_URL}" "${WS_SRC}/doosan-robot2"
fi

# 3) 레포 host 패키지를 ws src 로 복사 (symlink 아님 — 워크스페이스가 레포/USB 위치에
#    의존하지 않도록). 레포가 소스 진실원본이므로 재실행 시 레포 기준으로 재동기화:
#    기존 대상(과거 버전이 만든 symlink 포함)을 지우고 새로 복사 → 재실행 안전.
#    누락 시 fail-loud: 경고만 하고 넘어가면 빌드는 성공(exit 0)하지만 워크스페이스에
#    해당 패키지가 빠진 채 state=DONE 이 되어, 런타임에 ROS2 토픽 부재로야 발견된다.
for pkg in "${HOST_PKGS[@]}"; do
    if [[ ! -d "${REPO_DIR}/cobot2_ws/${pkg}" ]]; then
        echo "dsr: host 패키지 소스 누락 — ${REPO_DIR}/cobot2_ws/${pkg}" >&2
        exit 1
    fi
    rm -rf "${WS_SRC:?}/${pkg}"
    cp -a "${REPO_DIR}/cobot2_ws/${pkg}" "${WS_SRC}/${pkg}"
done

# 4) DSR 빌드 의존 apt 패키지 (a01 ros2-install.sh / desktop 코어에 없는 DSR 전용만).
#    나머지 선언적 의존은 colcon-build.sh 의 rosdep install 이 자동 해소.
sudo apt-get update
sudo apt-get install -y \
    "ros-${ROS_DISTRO}-velocity-controllers" \
    "ros-${ROS_DISTRO}-eigen3-cmake-module"

# 5) DSR 에뮬레이터 이미지 (명시 태그 — 이미 있으면 docker 가 자동 skip).
docker pull "doosanrobot/dsr_emulator:${DSR_EMULATOR_VERSION}"

echo "success installing Doosan DSR (${DSR_BRANCH}) + emulator ${DSR_EMULATOR_VERSION}"
