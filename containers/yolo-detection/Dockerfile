# syntax=docker/dockerfile:1.7
#
# yolo-detection 컨테이너 — object_detection ROS2 노드 (service server /get_3d_position).
# base = ros:jazzy-ros-base-noble 핀 (Hard Rule #6, latest 금지).
# CUDA 는 OS 에 설치하지 않는다: PyTorch cu128 wheel 이 CUDA 런타임을 자체 번들하고,
# GPU 는 런타임에 nvidia-container-toolkit 가 host driver 를 주입 → nvidia/cuda base 불필요.
# multi-stage: builder(빌드 도구) → runtime(실행 의존만) 으로 build-essential/pip cache 제거.

ARG ROS_DISTRO=jazzy

############################ builder ############################
FROM ros:${ROS_DISTRO}-ros-base-noble AS builder
SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG ROS_DISTRO=jazzy
# pip PyTorch index 용 CUDA 메이저 (resources/config.sh 의 CUDA_VERSION, 기본 12.8 → cu128).
ARG CUDA_VERSION=12.8

# 빌드/툴체인 의존: colcon, rosdep, rosidl 생성기(od_msg 빌드용 — od_msg package.xml 은
# 원본 보존이라 toolchain 을 명시 설치), cv_bridge/sensor_msgs (object_detection 빌드).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      python3-dev \
      python3-pip \
      python3-colcon-common-extensions \
      python3-rosdep \
      ros-${ROS_DISTRO}-rosidl-default-generators \
      ros-${ROS_DISTRO}-cv-bridge \
      ros-${ROS_DISTRO}-sensor-msgs \
 && rm -rf /var/lib/apt/lists/*

# --- pip 레이어를 소스 COPY 보다 앞에 배치 ---
# 노드 소스(object_detection/yolo.py 등)만 고쳐도 torch(가장 무거운 레이어)가 재다운로드되지
# 않도록, 소스와 무관한 pip 설치를 소스 COPY 앞에 둔다.
#
# PEP 668: noble 의 system python 은 /usr/lib/python3.12/EXTERNALLY-MANAGED 로 pip 을 차단한다
# → --break-system-packages 로 해제. pip 설치본은 /usr/local/lib/python3.X/dist-packages 로 가고
# apt 영역(/usr/lib/python3/dist-packages)과 디렉토리가 분리된다. 이 경로는 system python 의
# 기본 sys.path 라 PYTHONPATH 주입 없이 `ros2 run` 의 콘솔스크립트(shebang = system python)가
# 그대로 import 한다.
#
# numpy 선행 설치가 필수다: apt 가 깐 numpy 는 pip RECORD 메타가 없어 pip 이 제거를 거부한다
# ("Cannot uninstall numpy 1.26.4, RECORD file not found. Hint: installed by debian") → 뒤따르는
# 패키지가 numpy 버전 변경을 요구하는 순간 설치 전체가 실패. --ignore-installed 로 pip 소유
# 사본을 /usr/local 에 먼저 만들어 두면, 이후 업/다운그레이드는 그 사본에서만 일어나고
# apt 사본은 손상 없이 남는다(dpkg 정합 유지).
RUN pip install --break-system-packages --no-cache-dir --ignore-installed "numpy<2"
# torch/torchvision (cu128) — 가장 무거운 레이어(CUDA 런타임 번들)라 단독 RUN 으로 캐시 분리.
RUN pip install --break-system-packages --no-cache-dir \
      --index-url "https://download.pytorch.org/whl/cu${CUDA_VERSION//./}" \
      torch==2.11.0 torchvision==0.26.0
# ultralytics → opencv-python 을 numpy<2 호환 마지막 버전(<4.10 = 4.9.0.80, numpy>=1.21.2)으로
# 다운그레이드해 numpy>=2 메타 충돌 제거 → numpy<2 마지막 재핀. 재핀 직후 import 검증.
# ultralytics 는 메이저 상한 핀 (실측 8.4.102). 메이저 변경 시 API 깨질 수 있어 silent drift 차단.
# 재핀은 --force-reinstall 없이 — /usr/local 의 pip 소유 numpy 만 갈아끼우면 되고, force 는
# 탐색이 apt 사본까지 내려가 그 파일을 지우려다 실패/손상시킬 수 있다.
RUN pip install --break-system-packages --no-cache-dir "ultralytics<9" \
 && pip install --break-system-packages --no-cache-dir "opencv-python<4.10" \
 && pip install --break-system-packages --no-cache-dir "numpy<2" \
 && python3 -c "import numpy, torch, ultralytics, cv2; assert numpy.__version__.startswith('1.'), numpy.__version__; assert '/usr/local/' in numpy.__file__, numpy.__file__"
# 슬리밍: 추론에 불요한 항목 제거 — triton(torch.compile 전용) / C++ 헤더 / 정적 .a / pycache.
# 경로의 python 버전은 base 이미지에서 동적으로 구함 (3.13 등으로 올라가도 슬리밍이 silent no-op 되지 않게).
# import 회귀는 runtime smoke(build-all.sh)가 검증. (nvidia CUDA .so 런타임은 GPU 필수라 유지.)
RUN PYVER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')" \
 && SP="/usr/local/lib/python${PYVER}/dist-packages" \
 && pip uninstall --break-system-packages -y triton 2>/dev/null || true \
 && rm -rf "${SP}/torch/include" \
 && find "${SP}/nvidia" -type d -name include -prune -exec rm -rf {} + 2>/dev/null || true \
 && find /usr/local/lib -name '*.a' -delete 2>/dev/null || true \
 && find /usr/local/lib -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true

# --- 소스 COPY: 여기부터 캐시가 무효화돼도 위 torch/pip 레이어는 보존된다. ---
# od_msg 를 먼저 둔다 (object_detection 이 from od_msg.srv import — colcon 이 위상정렬).
COPY cobot_ws/src/cobot2/yolo_container/od_msg           /ws/src/od_msg
COPY cobot_ws/src/cobot2/yolo_container/object_detection /ws/src/object_detection

WORKDIR /ws
# object_detection 의 선언적 의존(rclpy/sensor_msgs/cv_bridge/ament_index_python/od_msg)을
# rosdep 으로 해소. ultralytics/numpy 는 pip 영역이라 rosdep key 없음 → skip.
RUN rosdep init 2>/dev/null || true \
 && rosdep update \
 && rosdep install --from-paths src --ignore-src --rosdistro "${ROS_DISTRO}" -y \
      --skip-keys "ultralytics numpy" \
 && rm -rf /var/lib/apt/lists/*

# setup.bash 는 unset var(AMENT_TRACE_SETUP_FILES 등)을 참조하므로 source 동안 -u 해제.
# 콘솔스크립트 shebang = system python 이고 pip 패키지도 그 python 의 sys.path(/usr/local)에 있어
# 런타임에 별도 경로 주입이 필요 없다.
RUN set +u \
 && source "/opt/ros/${ROS_DISTRO}/setup.bash" \
 && colcon build --merge-install

# rmw-cyclonedds-cpp: dev override(docker-compose.dev.yml)는 이 builder 이미지에서 직접 노드를 기동하는데
# compose 가 RMW=rmw_cyclonedds_cpp 를 강제한다. ros-base 기본은 fastrtps 라, builder 에 cyclonedds 구현을
# 명시 설치하지 않으면 dev 노드가 RMW 로드에 실패한다(runtime 스테이지엔 있으나 dev 는 builder 를 그대로 쓴다).
# 무거운 torch/pip 레이어 뒤 별도 레이어로 둬 추가 시에도 그 캐시를 보존한다.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ros-${ROS_DISTRO}-rmw-cyclonedds-cpp \
 && rm -rf /var/lib/apt/lists/*

############################ runtime ############################
FROM ros:${ROS_DISTRO}-ros-base-noble AS runtime
SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG ROS_DISTRO=jazzy

# 실행 의존만: cv_bridge/sensor_msgs. 카메라(realsense2_camera)는 host 에서 실행하고
# 이 컨테이너의 object_detection 노드는 host 가 publish 하는 /camera/camera/* 토픽
# (color/aligned_depth_to_color/camera_info)을 DDS 로 subscribe 한다 → 컨테이너 안에
# realsense2_camera 드라이버나 USB passthrough 가 필요 없다. cv_bridge(Image↔cv2) 와
# sensor_msgs(구독 메시지 타입)는 노드 런타임에 필수라 유지.
# rmw-cyclonedds-cpp: host↔컨테이너가 같은 topic/service 를 보려면 RMW 가 일치해야 한다
# (compose 가 RMW_IMPLEMENTATION=rmw_cyclonedds_cpp 로 기동). ros-base 기본 RMW 는 fastrtps 라
# cyclonedds 구현을 명시 설치하지 않으면 런타임에 RMW 로드 실패 → 같은 도메인이어도 host 토픽
# 미발견. host(설치 단계가 cyclonedds RMW 설치)와 짝을 맞춘다.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ros-${ROS_DISTRO}-cv-bridge \
      ros-${ROS_DISTRO}-sensor-msgs \
      ros-${ROS_DISTRO}-rmw-cyclonedds-cpp \
 && rm -rf /var/lib/apt/lists/*

# pip 설치본(/usr/local/lib/python3.X/dist-packages)과 콘솔스크립트(/usr/local/bin)를 통째 이관.
# 버전 디렉토리를 하드코딩하지 않으려 /usr/local/lib 를 그대로 옮긴다(base 이미지의 해당 경로는
# python3.X 빈 트리뿐이라 덮어쓸 것이 없다). /usr/local/bin 은 base PATH 에 이미 포함.
COPY --from=builder /usr/local/lib /usr/local/lib
COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=builder /ws/install   /ws/install

COPY containers/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["ros2", "run", "object_detection", "object_detection"]
