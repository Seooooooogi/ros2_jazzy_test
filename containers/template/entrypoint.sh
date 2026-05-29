#!/usr/bin/env bash
# ENTRYPOINT — 모든 컨테이너 실행 시 ROS2 환경을 source 한 뒤 사용자 명령으로 exec.
set -euo pipefail

# /opt/ros/${ROS_DISTRO}/setup.bash 는 unset var 참조가 있어 set -u 하에서 깨질 수 있음.
# source 직전만 일시적으로 -u 해제.
set +u
# shellcheck source=/dev/null
source "/opt/ros/${ROS_DISTRO}/setup.bash"
set -u

exec "$@"
