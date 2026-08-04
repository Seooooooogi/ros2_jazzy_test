#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/app-install.sh — 워크스페이스와 앱 계층 설치. base 설치가 끝난 뒤 setup-app.sh 가 부른다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
config_assert_set

# Doosan 로봇 드라이버 소스 clone + DSR 전용 apt 패키지 + 에뮬레이터 이미지.
# 소스는 커밋으로, 이미지는 태그로 고정한다 — 설치 시점마다 다른 것이 깔리면 재현이 안 된다.
app_dsr() {
    local WS_SRC="${DSR_WORKSPACE}/src"

    # 1) 워크스페이스 src 디렉토리.
    mkdir -p "${WS_SRC}"

    # 2) doosan-robot2 clone — .git 이 있으면 건너뛴다.
    if [[ -d "${WS_SRC}/doosan-robot2/.git" ]]; then
        echo "dsr: doosan-robot2 already cloned (skip)"
        # 이미 있는 작업본은 checkout 으로 덮어쓰지 않는다(개발 중 변경 보호). 대신 핀과 어긋나면
        # 알린다 — 조용히 넘기면 "저 머신에선 되는데" 를 추적할 방법이 없어진다.
        DSR_HEAD="$(git -C "${WS_SRC}/doosan-robot2" rev-parse HEAD)"
        if [[ "${DSR_HEAD}" != "${DSR_COMMIT}" ]]; then
            echo "dsr: warning — 기존 clone 이 핀과 다름 (${DSR_HEAD:0:8} != ${DSR_COMMIT:0:8})" >&2
            echo "dsr:           핀에 맞추려면: git -C ${WS_SRC}/doosan-robot2 checkout --detach ${DSR_COMMIT}" >&2
        fi
    else
        # fork 에는 'jazzy' 브랜치가 없어 -b "${DSR_BRANCH}" 를 주면 clone 자체가 실패한다.
        # 기본 브랜치로 받은 뒤 핀 커밋으로 detach — fork 에 커밋이 얹혀도 설치 결과가 안 흔들린다.
        git clone "${DSR_REPO_URL}" "${WS_SRC}/doosan-robot2"
        git -C "${WS_SRC}/doosan-robot2" checkout --detach "${DSR_COMMIT}"
    fi

    # cobot2 앱 소스는 이 레포가 제공하지 않는다 — 사용자가 ${WS_SRC}/cobot2 에 직접 두고,
    # setup-app.sh 가 빌드 전에 존재를 확인한다.

    # 3) DSR 전용 apt 패키지만 여기서. 나머지 의존성은 colcon 단계의 rosdep 이 알아서 해결한다.
    sudo apt-get update
    sudo apt-get install -y \
        "ros-${ROS_DISTRO}-velocity-controllers" \
        "ros-${ROS_DISTRO}-eigen3-cmake-module"

    # 3b) robot_control 노드가 런타임에 import 하는 Python 패키지 — scipy(좌표 변환) / numpy /
    #     pymodbus(그리퍼 Modbus 통신). 이 노드는 host 에서 돌기 때문에 host 에 있어야 한다.
    #     colcon 빌드는 import 를 하지 않아 없어도 통과하고, 실제로는 `ros2 run` 에서야 깨진다.
    #     venv 가 아니라 apt 로 까는 이유: 별도 활성화 없이 system Python 이 그대로 보게 하려고.
    sudo apt-get install -y \
        python3-numpy python3-scipy python3-pymodbus

    # 4) DSR 에뮬레이터 이미지. 태그를 명시해 latest 로 조용히 밀리지 않게 한다.
    docker pull "doosanrobot/dsr_emulator:${DSR_EMULATOR_VERSION}"

    echo "dsr: success installing Doosan DSR (${DSR_BRANCH}) + emulator ${DSR_EMULATOR_VERSION}"
}

# RealSense 카메라의 librealsense2 SDK(커널 모듈 + 유틸 + 헤더) 설치. apt 저장소·키링 등록 포함.
# RealSense 가 Intel 에서 분사하며 저장소 도메인과 서명 키가 함께 바뀌었다 — 옛 Intel 키로는 지금
# 저장소의 서명을 검증하지 못해 apt update 가 NO_PUBKEY 로 막힌다. 그래서 새 도메인의 armored 키를 쓴다.
# 커널 모듈은 DKMS(커널이 바뀔 때마다 모듈을 자동 재빌드하는 구조)로 빌드되고 그때 커널 헤더가 필요해,
# HWE 헤더 메타와 현재 커널 헤더를 함께 깐다 — 메타가 있어야 커널이 올라가도 재빌드가 안 깨진다.
realsense_sdk() {
    local RS_KEY="${KEYRING_DIR}/librealsenseai.gpg"
    local RS_LIST=/etc/apt/sources.list.d/librealsenseai.list
    local RS_KEY_URL="https://librealsense.realsenseai.com/Debian/librealsenseai.asc"
    local RS_REPO="https://librealsense.realsenseai.com/Debian/apt-repo"

    # 0) 예전 Intel 키/소스가 남아 있으면 먼저 지운다 — 그대로 두면 그 저장소의 NO_PUBKEY 때문에
    #    아래 첫 apt update 부터 막힌다. 이 파일들은 이 설치기가 만든 것이라 다시 생성된다.
    sudo rm -f /etc/apt/sources.list.d/librealsense.list "${KEYRING_DIR}/librealsense.pgp"

    # 1) 사전 도구 + 커널 헤더(DKMS 빌드용 — HWE 헤더 메타 + 지금 부팅된 커널).
    sudo apt-get update
    sudo apt-get install -y curl ca-certificates gnupg apt-transport-https \
        "${KERNEL_HEADERS_META}" "linux-headers-$(uname -r)"
    # 2) 키링 + apt 소스.
    add_apt_repo \
        --mode dearmor --downloader curl-sSf --key-write tee \
        --key-url "${RS_KEY_URL}" --key-file "${RS_KEY}" \
        --list-file "${RS_LIST}" \
        --list-line "deb [signed-by=${RS_KEY}] ${RS_REPO} ${UBUNTU_CODENAME} main"

    # 4) SDK 본체 — 커널 모듈 + 유틸 + 헤더 + 디버그 심볼.
    sudo apt-get install -y \
        librealsense2-dkms \
        librealsense2-utils \
        librealsense2-dev \
        librealsense2-dbg

    echo "realsense-sdk: success installing RealSense librealsense2 SDK (${UBUNTU_CODENAME} apt repo)"
}

# RealSense 를 ROS2 토픽으로 내보내는 wrapper 패키지(camera + description). SDK 가 먼저 깔려 있어야 한다.
# glob 대신 패키지 이름을 명시해 어느 머신에서 돌려도 같은 것이 깔리게 한다.
realsense_ros() {
    sudo apt-get update

    # ROS2 바이너리 패키지들은 통째로 한 snapshot 이다. 패키지 간 의존 표기가 느슨해 서로 다른 시점의
    # 패키지가 섞이면, 먼저 깔려 있던 diagnostic_updater 가 더 오래돼 realsense2_camera 가 로드
    # 시점에 undefined symbol 로 죽는다. apt 는 그 옛 패키지를 알아서 올려주지 않으므로, 이미 설치된
    # ROS 패키지만 현재 snapshot 으로 다시 맞춘다. 전체 apt upgrade 를 안 쓰고 ros-${ROS_DISTRO}-*
    # 로 범위를 좁히는 이유는 hold 로 고정해 둔 docker/nvidia 버전을 건드리지 않기 위해서다.
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

# 음성 노드가 쓰는 Python 스택(langchain / openai / 호출어 감지)을 host 에 직접 설치한다.
# 컨테이너에 넣지 않는 이유: 마이크가 하드웨어에 묶여 컨테이너로 오디오를 넘기는 방식이 머신마다 깨졌다.
app_voice() {
    local OWW_SRC="${SCRIPT_DIR}/oww_models"
    local WAKEWORD_MODEL="${VOICE_WS}/resource/hello_rokey_8332_32.tflite"

    # 아래에서 쓰는 ai-edge-litert 가 Python 3.12 wheel 만 있어서, 다른 버전이면 여기서 바로 멈춘다.
    local PYVER
    PYVER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    if [[ "${PYVER}" != "3.12" ]]; then
        echo "voice-host-install: Python 3.12 기대(noble), 실제 ${PYVER} — ai-edge-litert wheel 전제 불충족" >&2
        exit 1
    fi

    # 1) 오디오 시스템 라이브러리 — portaudio 는 PyAudio/sounddevice 가, libsndfile 은 soundfile 이,
    #    ffmpeg 은 오디오 디코드가 쓴다(-dev 는 pyaudio 컴파일용).
    echo "[voice-host-install] 1/6 시스템 라이브러리(apt)"
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends \
        python3-dev python3-pip \
        portaudio19-dev libportaudio2 libsndfile1 libasound2-dev ffmpeg

    # sudo 로 system site-packages 에 설치해야 모든 셸의 `ros2 run` 이 그대로 본다. non-root pip 는
    # ~/.local 로 빠질지가 버전마다 갈려 설치 위치를 확정할 수 없다.
    # Ubuntu 는 system Python 을 apt 가 관리한다며 pip 설치를 막으므로 --break-system-packages 로 연다.
    local PIP=(sudo python3 -m pip install --break-system-packages --no-cache-dir)

    # 2) 음성/LLM 스택. scipy 는 1.18 부터 numpy>=2 를 요구해 마지막의 numpy<2 고정과 충돌하므로 상한을 둔다.
    echo "[voice-host-install] 2/6 langchain / openai / 음성 스택"
    # openai 가 apt 로 깔린 typing-extensions 를 올리려 하는데, dpkg 로 설치된 것은 pip 가 지울 수
    # 없어("RECORD file not found") 그대로 두면 실패한다. 상위 버전을 먼저 얹어 apt 본을 가리면
    # 이후 단계는 이미 충족으로 보고 삭제를 시도하지 않는다.
    # ponytail: 이런 식으로 걸리는 apt 파이썬 패키지는 지금 typing-extensions 뿐. 늘어나면 여기 한 줄 추가.
    "${PIP[@]}" --ignore-installed --no-deps "typing-extensions>=4.14,<5"
    "${PIP[@]}" \
        "langchain<2" "langchain-openai<2" "openai<3" \
        pyaudio sounddevice "scipy<1.18" python-dotenv

    # 3) openwakeword(호출어 감지). 의존성에 3.12 wheel 이 없는 tflite-runtime 이 걸려 있어 --no-deps 로 깐다.
    echo "[voice-host-install] 3/6 openwakeword(--no-deps)"
    "${PIP[@]}" --no-deps "openwakeword==0.6.0"

    # 4) 그래서 빠진 실제 의존성을 직접 깔고, tflite-runtime 자리에는 API 가 같은 ai-edge-litert 를 넣는다.
    echo "[voice-host-install] 4/6 openwakeword 의존 + ai-edge-litert"
    "${PIP[@]}" \
        "onnxruntime<2,>=1.10.0" "tqdm<5,>=4.0" "scikit-learn<2,>=1" "requests<3,>=2.0" \
        "ai-edge-litert>=2.0.2,<3"
    # openwakeword 코드가 `import tflite_runtime.interpreter` 를 그대로 부르므로, 그 이름을
    # ai_edge_litert 로 이어 주는 최소 모듈을 site-packages 에 만들어 둔다.
    sudo python3 -c "import os,ai_edge_litert as a; d=os.path.join(os.path.dirname(os.path.dirname(a.__file__)),'tflite_runtime'); os.makedirs(d,exist_ok=True); open(os.path.join(d,'__init__.py'),'w').close(); open(os.path.join(d,'interpreter.py'),'w').write('from ai_edge_litert.interpreter import Interpreter  # noqa: F401\n')"

    # 5) 모델 채워 넣기: 동봉 모델 복사 → 나머지 모델 다운로드 → 전부 온전한지 검증.
    #    openwakeword 설치 경로는 root 소유라 일반 사용자로 도는 런타임이 여기에 쓰지 못한다. 그래서
    #    런타임이 받으려 할 모델을 설치할 때 미리 채워 둔다 — 이미 있는 파일은 건너뛰므로 런타임의
    #    다운로드 호출이 아무 일도 하지 않게 된다.
    #    다운로드가 일시적으로 실패하면 에러 HTML 이 .tflite 이름으로 저장돼 런타임에서야 터졌다.
    #    그래서 받은 뒤 파일 시그니처를 확인하고, 깨진 것은 지우고 여기서 멈춘다(다시 실행하면 새로 받는다).
    echo "[voice-host-install] 5/6 feature 복사 + stock 모델 다운로드 + TFL3 검증"
    # sudo 는 환경변수를 지우므로 OWW_SRC 는 env 로 넘긴다.
    sudo env "OWW_SRC=${OWW_SRC}" python3 - <<'PY'
import os, shutil, openwakeword, openwakeword.utils
src = os.environ["OWW_SRC"]
dst = os.path.join(os.path.dirname(openwakeword.__file__), "resources", "models")
os.makedirs(dst, exist_ok=True)
# (a) bundled feature 모델 복사 (네트워크 우회 — 동봉본이 authoritative).
for f in os.listdir(src):
    shutil.copy(os.path.join(src, f), dst)
# (b) stock wakeword 모델 다운로드. feature 는 이미 존재 → 존재-가드로 skip, VAD+stock 만 네트워크에서.
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

    # 6) numpy 를 1.x 로 되돌린다 — 앞의 pip 단계 중 하나가 2.x 를 끌어왔을 수 있고, 이 스택은 1.x 로만
    #    검증돼 있다. 이미 1.x 면 아무 일도 일어나지 않는다.
    echo "[voice-host-install] 6/6 numpy<2 보장 + import 검증"
    "${PIP[@]}" "numpy<2"

    # 검증 — openwakeword 는 import 만으론 부족하다(모델을 런타임에야 읽는다). 실제 모델을 올려
    # 한 번 추론까지 돌려 봐야 여기서 실패를 잡을 수 있다.
    if [[ ! -f "${WAKEWORD_MODEL}" ]]; then
        echo "voice-host-install: wakeword 모델 없음 — ${WAKEWORD_MODEL}" >&2
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
print(f"  voice-host-install import OK — numpy {numpy.__version__}, "
      f"tflite shim -> {tflite_runtime.interpreter.Interpreter.__module__}, Model(.tflite) load + predict OK")
PY

    echo "success installing host voice application Python (system, --break-system-packages)"
}

# 워크스페이스를 colcon 으로 빌드한다.
# DSR 과 RealSense 설치가 모두 끝난 뒤 한 번만 부른다 — 앞 단계마다 빌드하면 같은 일을 여러 번 한다.
app_colcon() {
    if [[ ! -d "${DSR_WORKSPACE}/src" ]]; then
        echo "colcon-build: ${DSR_WORKSPACE}/src missing — the DSR install step must run first" >&2
        exit 1
    fi

    # ROS2 환경 로드. setup.bash 는 미정의 변수를 건드려서 set -u 를 잠시 꺼야 한다.
    set +u
    # shellcheck disable=SC1090,SC1091
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
    set -u

    # CycloneDDS RMW 패키지가 빌드 전제 조건이다 — config.sh 가 기본 RMW 를 cyclonedds 로 고정해 둬서,
    # 이게 없으면 dsr_msgs2 같은 패키지가 CMake 단계에서 미들웨어를 못 찾아 실패한다.
    # ROS desktop 은 Fast-DDS 만 깔아 주므로 별도 패키지인 이것을 여기서 챙긴다.
    if ! dpkg -s "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp" >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp"
    fi

    cd "${DSR_WORKSPACE}"

    # rosdep 이 워크스페이스 패키지들의 선언된 의존성을 대신 깔아 준다(init 은 앞 설치에서 끝났다).
    rosdep update
    # 건너뛰는 키: librealsense2 는 apt 로 직접 깐 네이티브 SDK 라 rosdep 키가 아니고,
    # message_generation/message_runtime 은 그리퍼 패키지에 남은 ROS1 잔재라 jazzy 에 규칙이 없다 —
    # 그대로 두면 실제로 쓰이지도 않는 키 때문에 이 단계가 통째로 실패한다.
    # 오류를 무시하고 진행하는 `-r` 은 쓰지 않는다 — 진짜 누락된 의존성까지 함께 가려진다.
    rosdep install --from-paths src --ignore-src --rosdistro "${ROS_DISTRO}" \
        --skip-keys="librealsense2 message_generation message_runtime" -y

    # object_detection 은 host 에서 못 돈다(torch 가 yolo 이미지 안에만 있다) → 빌드에서 뺀다.
    # voice_processing 은 host 에서 그대로 실행되므로 여기서 함께 빌드한다.
    colcon build --packages-skip object_detection

    # wakeword 모델이 빌드 산출물(install/)에도 들어갔는지 확인한다. 런타임은 소스 트리가 아니라
    # 설치된 패키지 경로에서 모델을 찾고, 앞의 voice 단계는 소스 트리만 볼 수 있었다 — setup.py 가
    # resource/ 를 설치하지 않는 경우를 잡을 수 있는 곳이 여기뿐이다.
    voice_share="${DSR_WORKSPACE}/install/voice_processing/share/voice_processing/resource"
    if [[ -d "${DSR_WORKSPACE}/install/voice_processing" ]] \
        && ! compgen -G "${voice_share}/*.tflite" >/dev/null; then
        echo "colcon-build: voice_processing 의 wakeword 모델이 설치 트리에 없음" >&2
        echo "           기대 경로: ${voice_share}/*.tflite" >&2
        echo "           voice_processing/setup.py 의 data_files 가 resource/ 를 설치하는지 확인." >&2
        exit 1
    fi

    echo "colcon-build: success building colcon workspace at ${DSR_WORKSPACE}"
}

# NVIDIA Container Toolkit 설치 + docker 에 nvidia runtime 등록.
# 이 도구는 host 의 드라이버 라이브러리와 GPU 장치를 컨테이너 안으로 넣어 준다(CUDA 런타임 자체는
# 이미 PyTorch wheel 안에 있다) — 없으면 yolo 컨테이너가 GPU 를 못 잡는다.
app_toolkit() {
    local TOOLKIT_LIST=/etc/apt/sources.list.d/nvidia-container-toolkit.list
    local TOOLKIT_KEY="${KEYRING_DIR}/nvidia-container-toolkit.gpg"

    # 0) 사전 조건 — 드라이버나 docker 가 없으면 반쪽 설치로 넘어가지 않고 바로 멈춘다.
    #    단 SKIP_IF_NO_GPU=1 이면 GPU 없는 머신으로 보고 에러가 아니라 정상 건너뛰기로 처리한다.
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

    # 1) 사전에 필요한 도구.
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg

    # 2) 키링 + apt source 등록. 설치 직전 update 는 아래 3) 에서 하므로 여기선 --no-update.
    add_apt_repo --no-update \
        --mode dearmor --downloader curl --key-write gpg-o \
        --key-url "https://nvidia.github.io/libnvidia-container/gpgkey" --key-file "${TOOLKIT_KEY}" \
        --list-file "${TOOLKIT_LIST}" \
        --list-url "https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list" \
        --list-sed "s#deb https://#deb [signed-by=${TOOLKIT_KEY}] https://#g" \
        --list-cmp cat

    # 3) 설치.
    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit

    # 4) docker 에 nvidia runtime 등록 — nvidia-ctk 가 /etc/docker/daemon.json 을 갱신한다.
    sudo nvidia-ctk runtime configure --runtime=docker

    # 5) 그 변경은 docker 재시작 후에야 반영된다. 재시작은 돌던 컨테이너를 멈추므로 동의를 받는다.
    if docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
        echo "nvidia-toolkit: the nvidia runtime is already registered with docker (skipping restart)."
    else
        confirm_or_abort_assumable "Restart the docker daemon to apply the nvidia runtime? (running containers will pause briefly)"
        sudo systemctl restart docker
    fi

    # 6) 검증 — runtime 이 등록됐는지 확인.
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
