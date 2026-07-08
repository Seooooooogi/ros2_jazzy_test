#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/dsr-project-install.sh — Doosan DSR(doosan-robot2) 드라이버 clone + 의존성 + 에뮬레이터 설치.
#
# backup/dsr-project-install{,_25}.sh 를 jazzy 로 옮기고 멱등(여러 번 실행해도 결과 동일)하게 만든 버전.
#   - ROKEY-SPARK fork 의 기본 브랜치(main = 버전 고정한 jazzy 스냅샷)를 clone. 이미 clone 돼 있으면
#     건너뜀(재현성 — git pull 안 함). fork 가 버전을 핀(고정)해 두어 upstream 이 push 해도 흔들리지 않음.
#   - 워크스페이스 = ${DSR_WORKSPACE}(=~/cobot_ws). 이 스크립트 = DSR 드라이버만 설치, doosan-robot2 는
#     ${DSR_WORKSPACE}/src 로 clone 됨. cobot2 앱 소스는 이 레포가 미제공 — 사용자가
#     ${DSR_WORKSPACE}/src/cobot2 에 직접 배치(setup-app.sh 가 colcon 빌드 전에 존재 확인).
#   - 에뮬레이터: doosanrobot/dsr_emulator:${DSR_EMULATOR_VERSION} 태그를 명시해서 pull.
#     이 태그는 config.sh 한 곳에서만 정의(apt/docker 의 latest 가 시간이 지나며 바뀜 방지). upstream
#     install_emulator.sh 도 똑같은 pull 만 하므로, 그걸 부르지 않고 여기서 바로 pull.
#   - rosdep update / colcon build 는 colcon-build.sh 가 담당(중복 빌드 방지).
# 순수 설치 본문 — state 호출 없음(단계 표시는 setup-app.sh 가 맡음).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

WS_SRC="${DSR_WORKSPACE}/src"
# 소스 고정(pin): upstream doosan-robotics/doosan-robot2 대신 ROKEY-SPARK fork 사용. fork 의
# 기본 브랜치(main)가 검증된 jazzy 스냅샷(upstream jazzy commit 816ecb5d) — 버전을 고정해서
# upstream 이 push 해도 설치가 흔들리지 않음, upstream 이 force-push/삭제해도 살아남음.
DSR_REPO_URL="https://github.com/ROKEY-SPARK/doosan-robot2_jazzy.git"


# 1) 워크스페이스 src 디렉토리.
mkdir -p "${WS_SRC}"

# 2) doosan-robot2 clone (멱등 — .git 이 있으면 건너뜀).
if [[ -d "${WS_SRC}/doosan-robot2/.git" ]]; then
    echo "dsr: doosan-robot2 already cloned (skip)"
else
    # fork 의 기본 브랜치(main = 버전 고정한 jazzy 스냅샷)를 clone. fork 에는 'jazzy' 브랜치가 없으므로
    # -b "${DSR_BRANCH}" 를 주면 안 됨("Remote branch not found" 로 실패).
    git clone "${DSR_REPO_URL}" "${WS_SRC}/doosan-robot2"
fi

# 2b) doosan-robot2 (jazzy) 소스 호환 패치 — DSR_ROBOT2.py 의 이름 불일치 2곳 수정(이 distro clone 대상).
#     둘 다 멱등(이미 올바르면 아무 것도 안 함) → 다시 실행하거나 다시 clone 해도 안전.
DSR_IMP_PY="${WS_SRC}/doosan-robot2/dsr_common2/imp/DSR_ROBOT2.py"
if [[ -f "${DSR_IMP_PY}" ]]; then
    # (1) 존재하지 않는 서비스 클래스 'SetSingularityHandlingForce'(Singular+ity)를 참조하고 있어서 →
    #     모듈을 로드하는 순간 NameError 가 나고 `import DSR_ROBOT2` 자체가 깨짐. dsr_msgs2 가 실제로 만드는
    #     클래스 이름 'SetSingularHandlingForce'(Singular)에 맞춤.
    if grep -q 'SetSingularityHandlingForce' "${DSR_IMP_PY}"; then
        sed -i 's/SetSingularityHandlingForce/SetSingularHandlingForce/g' "${DSR_IMP_PY}"
        echo "dsr: patched DSR_ROBOT2.py service class name (SetSingularityHandlingForce → SetSingularHandlingForce)"
    fi
    # (2) 서비스/토픽 이름 prefix 가 비어('') 있어서, 클라이언트는 '/<ns>/aux_control/...' 를 부르는데
    #     실제 컨트롤러(dsr_controller2)는 '/<ns>/dsr_controller2/...' 를 광고(advertise).
    #     → 그 이름의 서버가 없어서 get_current_posj 같은 호출이 영원히 대기. prefix 에 'dsr_controller2/' 를 채워
    #     클라이언트가 진짜 서버를 향하게 함(모듈 레벨만; 들여쓴 클래스 안쪽 버전은 미변경).
    if grep -qE "^_srv_name_prefix[[:space:]]*=[[:space:]]*''" "${DSR_IMP_PY}"; then
        sed -i -E "s|^_srv_name_prefix([[:space:]]*)=[[:space:]]*''|_srv_name_prefix\1= 'dsr_controller2/'|" "${DSR_IMP_PY}"
        echo "dsr: patched DSR_ROBOT2.py service prefix ('' → 'dsr_controller2/')"
    fi
else
    echo "dsr: DSR_ROBOT2.py missing — patch skipped (verify the clone)" >&2
fi

# cobot2 앱 소스는 여기에 미러링 안 함 — 이 레포는 더 이상 미제공. 사용자가
# ${WS_SRC}/cobot2 에 직접 배치; setup-app.sh 가 colcon-build.sh 를 부르기 전에 존재 확인(없으면 곧바로 실패).

# 3) DSR 빌드에 필요한 apt 패키지 (a01 ros2-install.sh / desktop core 에 없는 DSR 전용 것만).
#    나머지 선언적(declarative) 의존성은 colcon-build.sh 의 rosdep install 이 자동 해결.
sudo apt-get update
sudo apt-get install -y \
    "ros-${ROS_DISTRO}-velocity-controllers" \
    "ros-${ROS_DISTRO}-eigen3-cmake-module"

# 3b) robot_control(host 클라이언트)의 런타임 Python 의존성 — 얇은 클라이언트라 system Python(apt)으로 설치.
#     이건 컨테이너 방식이라 앱 Python(torch/ultralytics/openwakeword)의 집은 yolo/voice 컨테이너지만,
#     robot_control 은 host 에서 도는 ROS2 노드라 scipy(좌표 변환)/numpy/pymodbus(그리퍼 Modbus 통신)는
#     host 에 있어야 함. ament_python 은 빌드할 때 import 하지 않아 colcon 은 통과하지만, ros2 run 은 런타임에 깨짐.
#     venv 대신 apt 를 쓰는 이유: host=system Python 책임을 지키고, 별도 activation 없이 ros2 run 이 이 패키지들을 보게 함.
#     noble apt 의 numpy(1.26, <2)면 충분(host 엔 ultralytics 없음); noble apt 의 pymodbus 는 3.x
#     (onrobot.py 를 3.x API 로 마이그레이션함).
sudo apt-get install -y \
    python3-numpy python3-scipy python3-pymodbus

# 4) DSR 에뮬레이터 이미지 (명시 태그 — 이미 있으면 docker 가 자동으로 건너뜀).
docker pull "doosanrobot/dsr_emulator:${DSR_EMULATOR_VERSION}"

echo "dsr: success installing Doosan DSR (${DSR_BRANCH}) + emulator ${DSR_EMULATOR_VERSION}"
