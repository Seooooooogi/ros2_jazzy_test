#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/dsr-project-install.sh — Doosan DSR(doosan-robot2) clone + 의존성 + 에뮬레이터 (a02 step 1).
#
# backup/dsr-project-install{,_25}.sh 의 jazzy 마이그레이션 + idempotency.
#   - clone 브랜치 -b ${DSR_BRANCH}(=jazzy). 이미 받은 경우 skip (재현성 — git pull 안 함).
#   - 워크스페이스 = ${DSR_WORKSPACE}(=~/cobot2_ws). 레포 cobot2_ws/ 의 host 패키지
#     (robot_control, od_msg, cobot2_bringup) 만 src/ 로 복사 — app/container 패키지
#     (object_detection / voice_processing / pick_and_place_* / rokey) 는 별도(yolo/voice) 컨테이너가
#     담당하므로 host ws 에서 제외. src/ 에 든 패키지만 빌드되어 범위가 자연히 한정됨.
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

# host colcon 빌드 대상 패키지 (CUDA/voice 의존 패키지는 컨테이너로 제외).
# cobot2_bringup = 통합 bringup launch 패키지(드라이버+카메라+컨테이너 기동, robot_control 제외).
HOST_PKGS=(robot_control od_msg cobot2_bringup)

# 1) 워크스페이스 src 디렉토리.
mkdir -p "${WS_SRC}"

# 2) doosan-robot2 clone (idempotent — .git 있으면 skip).
if [[ -d "${WS_SRC}/doosan-robot2/.git" ]]; then
    echo "dsr: doosan-robot2 이미 clone 됨 (skip)"
else
    git clone -b "${DSR_BRANCH}" "${DSR_REPO_URL}" "${WS_SRC}/doosan-robot2"
fi

# 2b) doosan-robot2(jazzy) 소스 호환 패치 — DSR_ROBOT2.py(이 distro clone) 의 두 이름 불일치를
#     바로잡는다. 둘 다 멱등(이미 맞으면 무동작) → 재실행/재clone 안전.
DSR_IMP_PY="${WS_SRC}/doosan-robot2/dsr_common2/imp/DSR_ROBOT2.py"
if [[ -f "${DSR_IMP_PY}" ]]; then
    # (1) 존재하지 않는 service 클래스 'SetSingularityHandlingForce'(Singular+ity) 참조 →
    #     모듈 로드 시점 NameError 로 `import DSR_ROBOT2` 자체가 깨진다. dsr_msgs2 가 빌드하는
    #     실제 클래스명 'SetSingularHandlingForce'(Singular) 로 맞춘다.
    if grep -q 'SetSingularityHandlingForce' "${DSR_IMP_PY}"; then
        sed -i 's/SetSingularityHandlingForce/SetSingularHandlingForce/g' "${DSR_IMP_PY}"
        echo "dsr: DSR_ROBOT2.py service 클래스명 패치 (SetSingularityHandlingForce → SetSingularHandlingForce)"
    fi
    # (2) service/topic 이름 prefix 가 비어 있어(''), 클라이언트가 '/<ns>/aux_control/...' 를
    #     부르는데 실제 컨트롤러(dsr_controller2)는 '/<ns>/dsr_controller2/...' 로 광고한다.
    #     → 서버 없는 이름이라 get_current_posj 등에서 무한 대기. prefix 를 'dsr_controller2/'
    #     로 채워 클라이언트가 실서버를 향하게 한다 (모듈 레벨만; 들여쓰기된 class 버전 제외).
    if grep -qE "^_srv_name_prefix[[:space:]]*=[[:space:]]*''" "${DSR_IMP_PY}"; then
        sed -i -E "s|^_srv_name_prefix([[:space:]]*)=[[:space:]]*''|_srv_name_prefix\1= 'dsr_controller2/'|" "${DSR_IMP_PY}"
        echo "dsr: DSR_ROBOT2.py service prefix 패치 ('' → 'dsr_controller2/')"
    fi
else
    echo "dsr: DSR_ROBOT2.py 없음 — 패치 skip (clone 확인 필요)" >&2
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

# 4b) robot_control(host client)의 런타임 Python 의존 — system Python(apt)으로 설치(thin client).
#     컨테이너 variant 라 앱 Python(torch/ultralytics/openwakeword)의 본거지는 yolo/voice 컨테이너지만,
#     robot_control 은 host 에서 실행되는 ROS2 노드라 scipy(좌표 변환)/numpy/pymodbus(gripper Modbus)가
#     host 에 필요하다. ament_python 은 빌드시 import 안 해 colcon 은 통과하나 ros2 run 런타임에 깨진다.
#     venv 대신 apt: host=system Python 책임을 유지하고 ros2 run 이 추가 활성화 없이 바로 본다.
#     numpy 는 noble apt(1.26, <2)로 충분(host 에 ultralytics 없음), pymodbus 는 noble apt 3.x
#     (onrobot.py 가 3.x API 로 이관됨).
sudo apt-get install -y \
    python3-numpy python3-scipy python3-pymodbus

# 5) DSR 에뮬레이터 이미지 (명시 태그 — 이미 있으면 docker 가 자동 skip).
docker pull "doosanrobot/dsr_emulator:${DSR_EMULATOR_VERSION}"

echo "dsr: success installing Doosan DSR (${DSR_BRANCH}) + emulator ${DSR_EMULATOR_VERSION}"
