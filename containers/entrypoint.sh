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

# venv(/opt/venv) 의 pip 패키지(torch/ultralytics/langchain 등)를 PYTHONPATH 에 노출한다.
# colcon build 가 venv 생성보다 먼저 돌아 ament 콘솔스크립트 shebang 이 시스템 python
# (/usr/bin/python3)으로 굳는데, 그 python 은 venv site-packages 를 보지 못해 `ros2 run`
# 으로 노드를 띄우면 ModuleNotFoundError 가 난다(예: ultralytics). venv python 은 시스템
# python 의 symlink(동일 인터프리터·동일 버전)라 site-packages 경로만 얹으면 import 가능.
for _venv_sp in /opt/venv/lib/python*/site-packages; do
    [[ -d "${_venv_sp}" ]] || continue
    export PYTHONPATH="${_venv_sp}${PYTHONPATH:+:${PYTHONPATH}}"
    break
done

exec "$@"
