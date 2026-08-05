#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# containers/entrypoint.sh · yolo 앱 컨테이너 ENTRYPOINT
#   순서 = ROS2 기본 환경 + colcon 오버레이(/ws/install) source → 사용자 전달 명령을 exec 실행
set -euo pipefail

# ROS2 / 오버레이 setup.bash = 미설정 변수 참조 → 이 구간만 set -u 해제
set +u
# shellcheck source=/dev/null
source "/opt/ros/${ROS_DISTRO}/setup.bash"
# colcon 오버레이 = 이미지 안에 있으면 source
if [[ -f /ws/install/setup.bash ]]; then
    # shellcheck source=/dev/null
    source /ws/install/setup.bash
fi
set -u

# pip 패키지 설치 위치 = system python 기본 sys.path → PYTHONPATH 주입 불필요

exec "$@"
