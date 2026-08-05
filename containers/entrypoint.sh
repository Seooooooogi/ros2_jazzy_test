#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# containers/entrypoint.sh · yolo 앱 컨테이너 ENTRYPOINT
#   순서 = ROS2 기본 환경 + colcon 오버레이(/ws/install) source → 사용자 전달 명령을 exec 실행
#   template/entrypoint.sh 확장 = 오버레이 source 한 줄 추가가 유일한 차이
set -euo pipefail

# /opt/ros/${ROS_DISTRO}/setup.bash + 오버레이 setup.bash = 둘 다 미설정(unset) 변수 참조
# set -u = 미설정 변수 사용 시 에러 → 스크립트 사망
#   → source 하는 이 구간에서만 -u 일시 해제
set +u
# shellcheck source=/dev/null
source "/opt/ros/${ROS_DISTRO}/setup.bash"
# colcon 오버레이 = 이미지 안에 빌드돼 있으면 source(od_msg / object_detection)
if [[ -f /ws/install/setup.bash ]]; then
    # shellcheck source=/dev/null
    source /ws/install/setup.bash
fi
set -u

# pip 패키지(torch/ultralytics 등) 설치 위치
#   --break-system-packages → system python 의 /usr/local/lib/python3.X/dist-packages
#   이 경로 = 기본 sys.path
#   → ament 콘솔 스크립트(shebang = /usr/bin/python3)가 그대로 import
#   → PYTHONPATH 주입 불필요

exec "$@"
