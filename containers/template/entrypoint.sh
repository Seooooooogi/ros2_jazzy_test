#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# containers/template/entrypoint.sh — 앱 컨테이너 공용 ENTRYPOINT 의 최소 템플릿(새 컨테이너가 복사해 시작점으로 삼음).
# 컨테이너 기동 때마다 ROS2 기본 환경 source → 사용자가 넘긴 명령을 exec 로 실행.
set -euo pipefail

# /opt/ros/${ROS_DISTRO}/setup.bash = 값이 안 잡힌(unset) 변수 참조 → set -u(미설정 변수 사용 시
# 에러) 상태에선 스크립트 죽음. source 하는 이 구간에서만 잠깐 -u 해제.
set +u
# shellcheck source=/dev/null
source "/opt/ros/${ROS_DISTRO}/setup.bash"
set -u

exec "$@"
