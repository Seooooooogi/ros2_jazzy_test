#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/app-install.sh · 워크스페이스 + 앱 계층 설치
#   호출자 = setup-app.sh(base 설치 완료 후)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
config_assert_set

# Doosan 로봇 드라이버 소스 clone + DSR 전용 apt 패키지 + 에뮬레이터 이미지
app_dsr() {
    local WS_SRC="${DSR_WORKSPACE}/src"

    # 1) 워크스페이스 src 디렉토리
    mkdir -p "${WS_SRC}"

    # 2) doosan-robot2 clone (.git 존재 → skip)
    if [[ -d "${WS_SRC}/doosan-robot2/.git" ]]; then
        echo "dsr: doosan-robot2 already cloned (skip)"
        DSR_HEAD="$(git -C "${WS_SRC}/doosan-robot2" rev-parse HEAD)"
        if [[ "${DSR_HEAD}" != "${DSR_COMMIT}" ]]; then
            echo "dsr: warning — 기존 clone 이 핀과 다름 (${DSR_HEAD:0:8} != ${DSR_COMMIT:0:8})" >&2
            echo "dsr:           핀에 맞추려면: git -C ${WS_SRC}/doosan-robot2 checkout --detach ${DSR_COMMIT}" >&2
        fi
    else
        git clone "${DSR_REPO_URL}" "${WS_SRC}/doosan-robot2"
        git -C "${WS_SRC}/doosan-robot2" checkout --detach "${DSR_COMMIT}"
    fi

    # cobot2 앱 소스 = 이 레포 미제공, 사용자가 ${WS_SRC}/cobot2 에 직접 배치

    # 3) DSR 전용 apt 패키지
    sudo apt-get update
    sudo apt-get install -y \
        "ros-${ROS_DISTRO}-velocity-controllers" \
        "ros-${ROS_DISTRO}-eigen3-cmake-module"

    # 3b) robot_control 노드가 런타임에 import 하는 Python 패키지
    sudo apt-get install -y \
        python3-numpy python3-scipy python3-pymodbus

    # 4) DSR 에뮬레이터 이미지(태그 고정)
    docker pull "doosanrobot/dsr_emulator:${DSR_EMULATOR_VERSION}"

    echo "dsr: success installing Doosan DSR (${DSR_BRANCH}) + emulator ${DSR_EMULATOR_VERSION}"
}

# RealSense 카메라 librealsense2 SDK(커널 모듈 + 유틸 + 헤더) 설치(apt 저장소·키링 등록 포함)
realsense_sdk() {
    local RS_KEY="${KEYRING_DIR}/librealsenseai.gpg"
    local RS_LIST=/etc/apt/sources.list.d/librealsenseai.list
    local RS_KEY_URL="https://librealsense.realsenseai.com/Debian/librealsenseai.asc"
    local RS_REPO="https://librealsense.realsenseai.com/Debian/apt-repo"

    # 0) 잔존하는 옛 Intel 키/소스 삭제
    sudo rm -f /etc/apt/sources.list.d/librealsense.list "${KEYRING_DIR}/librealsense.pgp"

    # 1) 사전 도구 + 커널 헤더
    sudo apt-get update
    sudo apt-get install -y curl ca-certificates gnupg apt-transport-https \
        "${KERNEL_HEADERS_META}" "linux-headers-$(uname -r)"
    # 2) 키링 + apt 소스
    add_apt_repo \
        --mode dearmor --downloader curl-sSf --key-write tee \
        --key-url "${RS_KEY_URL}" --key-file "${RS_KEY}" \
        --list-file "${RS_LIST}" \
        --list-line "deb [signed-by=${RS_KEY}] ${RS_REPO} ${UBUNTU_CODENAME} main"

    # 4) SDK 본체 = 커널 모듈 + 유틸 + 헤더 + 디버그 심볼
    sudo apt-get install -y \
        librealsense2-dkms \
        librealsense2-utils \
        librealsense2-dev \
        librealsense2-dbg

    echo "realsense-sdk: success installing RealSense librealsense2 SDK (${UBUNTU_CODENAME} apt repo)"
}

# RealSense → ROS2 토픽 변환 wrapper 패키지(camera + description)
realsense_ros() {
    sudo apt-get update

    # 이미 설치된 ROS 패키지만 현재 snapshot 으로 재정렬
    local ros_installed
    ros_installed="$(dpkg-query -W -f='${db:Status-Status} ${Package}\n' "ros-${ROS_DISTRO}-*" 2>/dev/null \
        | awk '$1 == "installed" { print $2 }' || true)"
    if [[ -n "${ros_installed}" ]]; then
        # shellcheck disable=SC2086  # 일부러 word-splitting 함: ros_installed 는 줄바꿈으로 구분된 패키지 목록
        sudo apt-get install -y --only-upgrade ${ros_installed}
    fi

    sudo apt-get install -y \
        "ros-${ROS_DISTRO}-realsense2-camera" \
        "ros-${ROS_DISTRO}-realsense2-description"

    echo "realsense-ros: success installing ROS2 ${ROS_DISTRO} realsense2 wrapper"
}

# 음성 노드용 Python 스택(langchain / openai / 호출어 감지) = host 직접 설치
app_voice() {
    local OWW_SRC="${SCRIPT_DIR}/oww_models"
    local WAKEWORD_MODEL="${VOICE_WS}/resource/hello_rokey_8332_32.tflite"

    # ai-edge-litert = Python 3.12 wheel 전용 → 버전 확인
    local PYVER
    PYVER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    if [[ "${PYVER}" != "3.12" ]]; then
        echo "voice: Python 3.12 기대(noble), 실제 ${PYVER} — ai-edge-litert wheel 전제 불충족" >&2
        exit 1
    fi

    # 1) 오디오 시스템 라이브러리
    echo "[voice] 1/6 시스템 라이브러리(apt)"
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends \
        python3-dev python3-pip \
        portaudio19-dev libportaudio2 libsndfile1 libasound2-dev ffmpeg

    # system site-packages 설치(sudo + --break-system-packages)
    local PIP=(sudo python3 -m pip install --break-system-packages --no-cache-dir)

    # 2) 음성/LLM 스택
    echo "[voice] 2/6 langchain / openai / 음성 스택"
    # apt 설치본 typing-extensions 를 상위 버전으로 가림
    "${PIP[@]}" --ignore-installed --no-deps "typing-extensions>=4.14,<5"
    "${PIP[@]}" \
        "langchain<2" "langchain-openai<2" "openai<3" \
        pyaudio sounddevice "scipy<1.18" python-dotenv

    # 3) openwakeword(호출어 감지)
    echo "[voice] 3/6 openwakeword(--no-deps)"
    "${PIP[@]}" --no-deps "openwakeword==0.6.0"

    # 4) openwakeword 의존성 직접 설치(tflite-runtime 자리 = ai-edge-litert)
    echo "[voice] 4/6 openwakeword 의존 + ai-edge-litert"
    "${PIP[@]}" \
        "onnxruntime<2,>=1.10.0" "tqdm<5,>=4.0" "scikit-learn<2,>=1" "requests<3,>=2.0" \
        "ai-edge-litert>=2.0.2,<3"
    # tflite_runtime 이름을 ai_edge_litert 로 잇는 최소 모듈 생성
    sudo python3 -c "import os,ai_edge_litert as a; d=os.path.join(os.path.dirname(os.path.dirname(a.__file__)),'tflite_runtime'); os.makedirs(d,exist_ok=True); open(os.path.join(d,'__init__.py'),'w').close(); open(os.path.join(d,'interpreter.py'),'w').write('from ai_edge_litert.interpreter import Interpreter  # noqa: F401\n')"

    # 5) 모델 채우기 = 동봉 모델 복사 → 나머지 모델 다운로드 → 전체 무결성 검증
    echo "[voice] 5/6 feature 복사 + stock 모델 다운로드 + TFL3 검증"
    # sudo = 환경변수 제거 → OWW_SRC 는 env 로 전달
    sudo env "OWW_SRC=${OWW_SRC}" python3 - <<'PY'
import os, shutil, openwakeword, openwakeword.utils
src = os.environ["OWW_SRC"]
dst = os.path.join(os.path.dirname(openwakeword.__file__), "resources", "models")
os.makedirs(dst, exist_ok=True)
# (a) bundled feature 모델 복사 (네트워크 우회 — 동봉본이 authoritative).
for f in os.listdir(src):
    shutil.copy(os.path.join(src, f), dst)
# (b) stock wakeword 모델 다운로드. feature + VAD 는 동봉본으로 이미 존재 → 존재-가드로 skip, stock 만 네트워크에서.
openwakeword.utils.download_models()
# (c) 전체 .tflite 'TFL3' 매직 검증. 손상본(504 HTML)은 삭제 후 fail-loud → 재실행 시 재다운로드.
bad = [f for f in sorted(os.listdir(dst))
       if f.endswith(".tflite") and open(os.path.join(dst, f), "rb").read(8)[4:8] != b"TFL3"]
for f in bad:
    os.remove(os.path.join(dst, f))
if bad:
    raise SystemExit("corrupt tflite (deleted, re-run to re-fetch): " + ", ".join(bad))
print("  models OK:", sorted(f for f in os.listdir(dst) if f.endswith(".tflite")))
PY

    # 6) numpy 1.x 복원
    echo "[voice] 6/6 numpy<2 보장 + import 검증"
    "${PIP[@]}" "numpy<2"

    # 검증
    if [[ ! -f "${WAKEWORD_MODEL}" ]]; then
        echo "voice: wakeword 모델 없음 — ${WAKEWORD_MODEL}" >&2
        echo "           cobot2 소스가 먼저 배치돼야 함(setup-app.sh obtain_cobot2 선행)." >&2
        exit 1
    fi
    WAKEWORD_MODEL="${WAKEWORD_MODEL}" python3 - <<'PY'
import os, numpy as np
import numpy, scipy, langchain, langchain_openai, openai, pyaudio, sounddevice  # noqa: F401
import openwakeword, ai_edge_litert, tflite_runtime.interpreter, dotenv          # noqa: F401
assert numpy.__version__.startswith("1."), numpy.__version__
from openwakeword.model import Model
m = Model(wakeword_models=[os.environ["WAKEWORD_MODEL"]])
m.predict(np.zeros(1280, dtype=np.int16))
print(f"  voice import OK — numpy {numpy.__version__}, "
      f"tflite shim -> {tflite_runtime.interpreter.Interpreter.__module__}, Model(.tflite) load + predict OK")
PY

    echo "success installing host voice application Python (system, --break-system-packages)"
}

# 워크스페이스 colcon 빌드
app_colcon() {
    if [[ ! -d "${DSR_WORKSPACE}/src" ]]; then
        echo "colcon: ${DSR_WORKSPACE}/src missing — the DSR install step must run first" >&2
        exit 1
    fi

    # ROS2 환경 로드
    set +u
    # shellcheck disable=SC1090,SC1091
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
    set -u

    # CycloneDDS RMW 패키지 = 빌드 전제 조건
    if ! dpkg -s "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp" >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp"
    fi

    cd "${DSR_WORKSPACE}"

    # rosdep = 워크스페이스 패키지들의 선언 의존성 대리 설치
    rosdep update
    # skip 키 목록
    rosdep install --from-paths src --ignore-src --rosdistro "${ROS_DISTRO}" \
        --skip-keys="librealsense2 message_generation message_runtime" -y

    # object_detection = host 실행 불가 → 빌드 제외
    colcon build --packages-skip object_detection

    # wakeword 모델의 빌드 산출물(install/) 반영 여부 확인
    voice_share="${DSR_WORKSPACE}/install/voice_processing/share/voice_processing/resource"
    if [[ -d "${DSR_WORKSPACE}/install/voice_processing" ]] \
        && ! compgen -G "${voice_share}/*.tflite" >/dev/null; then
        echo "colcon: voice_processing 의 wakeword 모델이 설치 트리에 없음" >&2
        echo "           기대 경로: ${voice_share}/*.tflite" >&2
        echo "           voice_processing/setup.py 의 data_files 가 resource/ 를 설치하는지 확인." >&2
        exit 1
    fi

    echo "colcon: success building colcon workspace at ${DSR_WORKSPACE}"
}

# NVIDIA Container Toolkit 설치 + docker 에 nvidia runtime 등록
app_toolkit() {
    local TOOLKIT_LIST=/etc/apt/sources.list.d/nvidia-container-toolkit.list
    local TOOLKIT_KEY="${KEYRING_DIR}/nvidia-container-toolkit.gpg"

    # 0) 사전 조건
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        if [[ "${SKIP_IF_NO_GPU:-0}" == "1" ]]; then
            echo "nvidia-toolkit: no nvidia-smi — treating as a GPU-less host-only configuration and skipping."
            exit 0
        fi
        echo "nvidia-toolkit: no nvidia-smi — the nvidia driver must be installed first." >&2
        exit 1
    fi
    if ! command -v docker >/dev/null 2>&1; then
        echo "nvidia-toolkit: no docker — docker must be installed first." >&2
        exit 1
    fi

    # 1) 사전 필요 도구
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg

    # 2) 키링 + apt source 등록
    add_apt_repo --no-update \
        --mode dearmor --downloader curl --key-write gpg-o \
        --key-url "https://nvidia.github.io/libnvidia-container/gpgkey" --key-file "${TOOLKIT_KEY}" \
        --list-file "${TOOLKIT_LIST}" \
        --list-url "https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list" \
        --list-sed "s#deb https://#deb [signed-by=${TOOLKIT_KEY}] https://#g" \
        --list-cmp cat

    # 3) 설치
    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit

    # 4) docker 에 nvidia runtime 등록
    sudo nvidia-ctk runtime configure --runtime=docker

    # 5) docker 재시작(사전 동의 수령)
    if docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
        echo "nvidia-toolkit: the nvidia runtime is already registered with docker (skipping restart)."
    else
        confirm_or_abort_assumable "Restart the docker daemon to apply the nvidia runtime? (running containers will pause briefly)"
        sudo systemctl restart docker
    fi

    # 6) 검증 = runtime 등록 여부 확인
    if ! docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
        echo "nvidia-toolkit: warning — the nvidia runtime is not visible to docker. Check with 'docker info'." >&2
        exit 1
    fi
    echo "nvidia-toolkit: OK — docker nvidia runtime registered ->"
    nvidia-ctk --version | head -1
}

case "${1:?app-install: subcommand required (dsr|realsense-sdk|realsense-ros|voice|colcon|toolkit)}" in
    dsr)           app_dsr ;;
    realsense-sdk) realsense_sdk ;;
    realsense-ros) realsense_ros ;;
    voice)         app_voice ;;
    colcon)        app_colcon ;;
    toolkit)       app_toolkit ;;
    *) echo "app-install: unknown subcommand '$1'" >&2; exit 2 ;;
esac
