#!/usr/bin/env bash
# Phase 4 application 컨테이너 (yolo / voice) 공용 ENTRYPOINT.
# ROS2 base 환경 + colcon overlay (/ws/install) 를 source 한 뒤 사용자 명령으로 exec.
# template/entrypoint.sh 의 확장본 — overlay source 한 줄이 추가된 차이.
set -euo pipefail

# /opt/ros/${ROS_DISTRO}/setup.bash 와 overlay setup.bash 모두 unset var 참조가 있어
# set -u 하에서 깨질 수 있다. source 구간만 일시적으로 -u 해제.
set +u
# shellcheck source=/dev/null
source "/opt/ros/${ROS_DISTRO}/setup.bash"
# colcon overlay — 이미지에 빌드돼 있으면 source (od_msg / object_detection / voice_processing).
if [[ -f /ws/install/setup.bash ]]; then
    # shellcheck source=/dev/null
    source /ws/install/setup.bash
fi
set -u

exec "$@"
