#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# containers/entrypoint.sh — 앱 컨테이너(yolo/voice) 공용 ENTRYPOINT.
# ROS2 기본 환경 + colcon 오버레이(/ws/install) source 후 → 사용자가 넘긴 명령을 exec 로 실행.
# template/entrypoint.sh 확장 — 오버레이 source 한 줄 추가가 유일한 차이.
set -euo pipefail

# /opt/ros/${ROS_DISTRO}/setup.bash 와 오버레이 setup.bash = 둘 다 값이 안 잡힌(unset) 변수 참조.
# set -u(미설정 변수 사용 시 에러) 상태 → 이게 스크립트를 죽임. source 하는 이 구간에서만 잠깐 -u 끔.
set +u
# shellcheck source=/dev/null
source "/opt/ros/${ROS_DISTRO}/setup.bash"
# colcon 오버레이 — 이미지 안에 빌드돼 있으면 source(od_msg / object_detection / voice_processing).
if [[ -f /ws/install/setup.bash ]]; then
    # shellcheck source=/dev/null
    source /ws/install/setup.bash
fi
set -u

# venv(/opt/venv)의 pip 패키지(torch/ultralytics/langchain 등)를 PYTHONPATH 에 노출.
# colcon build 가 venv 생성보다 먼저 돌기 때문에, ament 콘솔 스크립트의 shebang(첫 줄 인터프리터 지정)이
# 시스템 python(/usr/bin/python3)으로 고정됨. 이 python 은 venv 의 site-packages 를 못 봐서
# `ros2 run` 으로 노드를 띄우면 ModuleNotFoundError(예: ultralytics) 발생. venv 의 python 은 시스템
# python 의 symlink(같은 인터프리터·같은 버전)라, site-packages 경로만 얹어 주면 import 됨.
for _venv_sp in /opt/venv/lib/python*/site-packages; do
    [[ -d "${_venv_sp}" ]] || continue
    export PYTHONPATH="${_venv_sp}${PYTHONPATH:+:${PYTHONPATH}}"
    break
done

exec "$@"
