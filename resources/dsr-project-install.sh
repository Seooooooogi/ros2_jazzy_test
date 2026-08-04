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
#   - ROKEY-SPARK fork 를 clone 한 뒤 DSR_COMMIT(config.sh) 으로 detach — fork main 은 동결본이
#     아니라 우리가 호환 패치를 얹는 곳이라 브랜치만으론 리비전이 고정되지 않는다. 이미 clone 돼
#     있으면 건너뜀(재현성 — git pull 안 함, 작업본 보호). 핀과 어긋나면 경고만 낸다.
#   - 워크스페이스 = ${DSR_WORKSPACE}(=~/cobot2_ws). 이 스크립트 = DSR 드라이버만 설치, doosan-robot2 는
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
# 소스는 upstream doosan-robotics/doosan-robot2 가 아니라 ROKEY-SPARK fork 를 쓴다 — upstream 이
# force-push/삭제해도 살아남고, 호환 패치를 얹을 수 있기 때문. 리비전 핀(DSR_COMMIT)은 config.sh.

# 1) 워크스페이스 src 디렉토리.
mkdir -p "${WS_SRC}"

# 2) doosan-robot2 clone (멱등 — .git 이 있으면 건너뜀).
if [[ -d "${WS_SRC}/doosan-robot2/.git" ]]; then
    echo "dsr: doosan-robot2 already cloned (skip)"
    # 기존 작업본은 checkout 으로 덮어쓰지 않는다 — 개발 중 변경을 날리지 않기 위함(cobot2 / M0609 와
    # 같은 원칙). 다만 핀과 어긋나면 알린다: 머신마다 다른 리비전으로 빌드되는 상태를 조용히 넘기면
    # "저 머신에선 되는데" 를 추적할 방법이 없어진다.
    DSR_HEAD="$(git -C "${WS_SRC}/doosan-robot2" rev-parse HEAD)"
    if [[ "${DSR_HEAD}" != "${DSR_COMMIT}" ]]; then
        echo "dsr: warning — 기존 clone 이 핀과 다름 (${DSR_HEAD:0:8} != ${DSR_COMMIT:0:8})" >&2
        echo "dsr:           핀에 맞추려면: git -C ${WS_SRC}/doosan-robot2 checkout --detach ${DSR_COMMIT}" >&2
    fi
else
    # fork 에는 'jazzy' 브랜치가 없으므로 -b "${DSR_BRANCH}" 를 주면 안 됨("Remote branch not found").
    # 기본 브랜치로 받은 뒤 핀 커밋으로 detach — fork main 에 커밋이 얹혀도 설치 결과가 안 흔들린다.
    git clone "${DSR_REPO_URL}" "${WS_SRC}/doosan-robot2"
    git -C "${WS_SRC}/doosan-robot2" checkout --detach "${DSR_COMMIT}"
fi

# DSR_ROBOT2.py 호환 패치(서비스 클래스명 SetSingular[ity]HandlingForce, _srv_name_prefix)는
# 여기서 sed 로 하지 않는다 — fork 커밋 f1118a1 이 이미 반영본이라 이 스크립트의 패치는 항상 no-op 였다.

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
