# syntax=docker/dockerfile:1.7
#
# voice-processing 컨테이너 — voice_processing ROS2 노드 (service server /get_keyword).
# base = ros:jazzy-ros-base-noble 핀 (Hard Rule #6). GPU 불요 (CPU 음성 파이프라인).
# OPENAI_API_KEY 는 이미지에 박지 않는다 — 런타임 env 주입 (ADR-007). 따라서 build-arg 에 secret 없음.
# multi-stage: builder(빌드 도구 + portaudio dev) → runtime(실행 의존만).

ARG ROS_DISTRO=jazzy

############################ builder ############################
FROM ros:${ROS_DISTRO}-ros-base-noble AS builder
SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG ROS_DISTRO=jazzy

# 빌드 의존: colcon/rosdep + PyAudio 컴파일용 portaudio dev + libsndfile(scipy/soundfile 계열).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      python3-dev \
      python3-venv \
      python3-pip \
      python3-colcon-common-extensions \
      python3-rosdep \
      portaudio19-dev \
      libsndfile1 \
 && rm -rf /var/lib/apt/lists/*

COPY cobot2_ws/voice_processing /ws/src/voice_processing

WORKDIR /ws
# voice_processing 의 선언적 의존(rclpy/std_srvs)을 rosdep 으로 해소.
RUN rosdep init 2>/dev/null || true \
 && rosdep update \
 && rosdep install --from-paths src --ignore-src --rosdistro "${ROS_DISTRO}" -y \
 && rm -rf /var/lib/apt/lists/*

# setup.bash 는 unset var(AMENT_TRACE_SETUP_FILES 등)을 참조하므로 source 동안 -u 해제.
RUN set +u \
 && source "/opt/ros/${ROS_DISTRO}/setup.bash" \
 && colcon build --merge-install

# Python 의존 venv 격리. 순서 = 음성/LLM 라이브러리 먼저 → numpy<2 마지막 재핀.
# openwakeword 가 tflite-runtime/onnxruntime 를 transitive 로 끌어온다.
RUN python3 -m venv --system-site-packages /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"
# 메이저 상한 핀 (실측: langchain 1.3.2 / langchain-openai 1.2.2 / openai 2.38 / scipy 1.17).
# langchain 은 메이저 사이에 import 경로가 바뀌므로(과거 langchain.prompts 제거) 상한 핀 특히 중요.
#
# openwakeword 0.6.0 의 wakeword 모델은 .tflite 라 tflite 백엔드가 필요한데, 0.6.0 은 의존으로
# tflite-runtime(>=2.8) 을 강제한다 — 그런데 tflite-runtime 은 Python 3.12 wheel 이 없다(최대 3.11).
# 해결: openwakeword 를 --no-deps 로 설치(불가능한 tflite-runtime 의존 회피) + 실제 의존을 명시 설치하되
# tflite-runtime 자리에 후속작 ai-edge-litert(cp312 wheel, 동일 Interpreter API)를 넣고,
# openwakeword 코드가 `import tflite_runtime.interpreter` 를 하드 호출하므로 ai_edge_litert 로 잇는
# 최소 shim 패키지를 site-packages 에 생성한다. 이로써 .tflite 모델/코드를 그대로 유지한 채 3.12 에서 동작.
# feature 모델(melspectrogram/embedding/VAD)은 wheel 에 미동봉 → download_models 로 받는다.
# 더미 model_names(['__feature_only__'])로 공식 사전학습 wakeword 모델 일괄 다운로드는 건너뛴다(커스텀 모델 사용).
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir \
      "langchain<2" "langchain-openai<2" "openai<3" \
      pyaudio sounddevice "scipy<2" python-dotenv \
 && pip install --no-cache-dir --no-deps "openwakeword==0.6.0" \
 && pip install --no-cache-dir \
      "onnxruntime<2,>=1.10.0" "tqdm<5,>=4.0" "scikit-learn<2,>=1" "requests<3,>=2.0" \
      "ai-edge-litert>=2.0.2,<3" \
 && python3 -c "import os,ai_edge_litert as a; d=os.path.join(os.path.dirname(os.path.dirname(a.__file__)),'tflite_runtime'); os.makedirs(d,exist_ok=True); open(os.path.join(d,'__init__.py'),'w').close(); open(os.path.join(d,'interpreter.py'),'w').write('from ai_edge_litert.interpreter import Interpreter  # noqa: F401\n')" \
 && python3 -c "import openwakeword.utils as u; u.download_models(['__feature_only__'])" \
 && pip install --no-cache-dir --force-reinstall "numpy<2" \
 && python3 -c "import numpy, langchain, langchain_openai, openai, pyaudio, sounddevice, scipy, openwakeword, ai_edge_litert, tflite_runtime.interpreter, dotenv; assert numpy.__version__.startswith('1.'), numpy.__version__"

############################ runtime ############################
FROM ros:${ROS_DISTRO}-ros-base-noble AS runtime
SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG ROS_DISTRO=jazzy

# 실행 의존: PyAudio 런타임(libportaudio2) + libsndfile + std_srvs(서비스 인터페이스).
# rmw-cyclonedds-cpp: host↔컨테이너 RMW 일치용(compose 가 cyclonedds 로 기동). ros-base 기본은
# fastrtps 라 명시 설치 안 하면 런타임 RMW 로드 실패 → host 토픽/서비스 미발견.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libportaudio2 \
      libsndfile1 \
      ros-${ROS_DISTRO}-std-srvs \
      ros-${ROS_DISTRO}-rmw-cyclonedds-cpp \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/venv   /opt/venv
COPY --from=builder /ws/install /ws/install
ENV PATH="/opt/venv/bin:${PATH}"

COPY containers/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["ros2", "run", "voice_processing", "get_keyword"]
