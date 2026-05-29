# syntax=docker/dockerfile:1.7
#
# ROS2 Jazzy (Ubuntu 24.04 / noble) base template image.
# Host installer 와 동일한 distro 핀 규약을 image build 에도 일관 적용.

FROM ubuntu:24.04

# 단일 진실 소스. 하위 이미지 (yolo / voice) 가 그대로 상속.
ARG ROS_DISTRO=jazzy
ENV ROS_DISTRO=${ROS_DISTRO}

# 모든 RUN 을 bash + fail-fast 로 실행 (호스트 스크립트의 set -euo pipefail 등가).
SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]

# build-time 동안만 비대화형 apt. ENV 가 아니므로 런타임에 새는 일 없음.
ARG DEBIAN_FRONTEND=noninteractive

# 1) Locale — ROS2 RMW 는 UTF-8 가정. 미설정 시 일부 메시지 직렬화 경로에서 경고/오류.
RUN apt-get update \
 && apt-get install -y --no-install-recommends locales \
 && locale-gen en_US en_US.UTF-8 \
 && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
 && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# 2) apt repo 추가에 필요한 최소 도구.
#    software-properties-common 은 add-apt-repository 제공.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      gnupg \
      software-properties-common \
 && rm -rf /var/lib/apt/lists/*

# 3) universe 활성화 — ROS2 의 다수 의존성 (예: libtinyxml2, libconsole-bridge) 이 universe 에 있음.
RUN add-apt-repository universe

# 4) ROS2 apt 키 + repo (현행 권장: /etc/apt/keyrings/ + signed-by, apt-key add 사용 안 함).
#    rosdistro 의 ros.key 는 이미 binary GPG 형식이라 dearmor 불필요.
RUN install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
      -o /etc/apt/keyrings/ros-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu noble main" \
      > /etc/apt/sources.list.d/ros2.list

# 5) ROS2 jazzy + 개발 도구 (colcon, rosdep, argcomplete).
#    rosdep init 은 root 에서 1회. rosdep update 는 user 영역이라 런타임에 수행.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ros-${ROS_DISTRO}-ros-base \
      python3-argcomplete \
      python3-colcon-common-extensions \
      python3-rosdep \
 && rosdep init \
 && rm -rf /var/lib/apt/lists/*

# 6) Entrypoint: 매 컨테이너 시작 시 ROS2 setup.bash 를 source.
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
