#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/activate.sh — One-shot ROS2 environment activation for non-interactive
# shells (CI / cron / systemd / scripted runs) where ~/.bashrc auto-source is not
# applied.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/activate.sh"
#   # 이후 ros2 / colcon / rclpy + 워크스페이스 패키지 + host venv 의 app Python 사용 가능.
#
# application-shell variant: application Python (PyTorch / ultralytics / openwakeword / langchain 등)
# 은 host venv(${HOST_VENV}) 에 있다. 본 wrapper 는 ROS2 + 워크스페이스 overlay + venv 를 함께 활성화한다.
# (`ros2 run` 은 entry_point shebang 이 이미 venv python 을 가리켜 venv 없이도 동작하지만, 직접
#  `python3 ...` 실행/디버깅 시 venv 활성화가 필요해 여기서 함께 켠다.)

_ACT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${_ACT_DIR}/config.sh"

if [[ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
else
    echo "activate: /opt/ros/${ROS_DISTRO}/setup.bash not found — ROS2 ${ROS_DISTRO} not installed?" >&2
fi

# 워크스페이스 overlay (colcon 빌드 후) — ros2 run/launch 가 host 패키지를 찾도록.
if [[ -f "${DSR_WORKSPACE}/install/setup.bash" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "${DSR_WORKSPACE}/install/setup.bash"
fi

# host venv (application Python) — python3 가 app 패키지를 보도록.
if [[ -d "${HOST_VENV}" ]]; then
    # shellcheck disable=SC1091
    source "${HOST_VENV}/bin/activate"
fi
