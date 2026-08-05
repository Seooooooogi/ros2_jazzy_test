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
# 고정(pin) 방식: 소스 = 커밋 / 이미지 = 태그(미고정 시 설치 시점마다 다른 버전 설치 → 재현 불가)
app_dsr() {
    local WS_SRC="${DSR_WORKSPACE}/src"

    # 1) 워크스페이스 src 디렉토리
    mkdir -p "${WS_SRC}"

    # 2) doosan-robot2 clone (.git 존재 → skip)
    if [[ -d "${WS_SRC}/doosan-robot2/.git" ]]; then
        echo "dsr: doosan-robot2 already cloned (skip)"
        # 기존 작업본 = checkout 으로 덮어쓰지 않음(개발 중 변경 보호)
        # 핀과 불일치 시 경고 출력(조용히 통과 → "저 머신에선 되는데" 추적 수단 소멸)
        DSR_HEAD="$(git -C "${WS_SRC}/doosan-robot2" rev-parse HEAD)"
        if [[ "${DSR_HEAD}" != "${DSR_COMMIT}" ]]; then
            echo "dsr: warning — 기존 clone 이 핀과 다름 (${DSR_HEAD:0:8} != ${DSR_COMMIT:0:8})" >&2
            echo "dsr:           핀에 맞추려면: git -C ${WS_SRC}/doosan-robot2 checkout --detach ${DSR_COMMIT}" >&2
        fi
    else
        # fork 에 'jazzy' 브랜치 없음 → -b "${DSR_BRANCH}" 지정 시 clone 자체 실패
        # 절차 = 기본 브랜치로 clone → 핀 커밋으로 detach → fork 에 커밋이 얹혀도 설치 결과 불변
        git clone "${DSR_REPO_URL}" "${WS_SRC}/doosan-robot2"
        git -C "${WS_SRC}/doosan-robot2" checkout --detach "${DSR_COMMIT}"
    fi

    # cobot2 앱 소스 = 이 레포 미제공
    #   배치 = 사용자가 ${WS_SRC}/cobot2 에 직접
    #   존재 확인 = setup-app.sh 가 빌드 전에 수행

    # 3) 여기서 다루는 것 = DSR 전용 apt 패키지만(나머지 의존성 = colcon 단계의 rosdep 이 해결)
    sudo apt-get update
    sudo apt-get install -y \
        "ros-${ROS_DISTRO}-velocity-controllers" \
        "ros-${ROS_DISTRO}-eigen3-cmake-module"

    # 3b) robot_control 노드가 런타임에 import 하는 Python 패키지
    #     scipy(좌표 변환) / numpy / pymodbus(그리퍼 Modbus 통신)
    #     이 노드 = host 실행 → host 설치 필수
    #     colcon 빌드 = import 미수행 → 누락돼도 통과, 실제 파손 시점 = `ros2 run`
    #     venv 아님, apt 설치(이유: 별도 활성화 없이 system Python 이 그대로 인식)
    sudo apt-get install -y \
        python3-numpy python3-scipy python3-pymodbus

    # 4) DSR 에뮬레이터 이미지(태그 명시 → latest 로 조용히 밀리는 것 차단)
    docker pull "doosanrobot/dsr_emulator:${DSR_EMULATOR_VERSION}"

    echo "dsr: success installing Doosan DSR (${DSR_BRANCH}) + emulator ${DSR_EMULATOR_VERSION}"
}

# RealSense 카메라 librealsense2 SDK(커널 모듈 + 유틸 + 헤더) 설치(apt 저장소·키링 등록 포함)
# RealSense = Intel 에서 분사 → 저장소 도메인 + 서명 키 동시 변경
#   옛 Intel 키 = 현 저장소 서명 검증 불가 → apt update 가 NO_PUBKEY 로 차단
#   → 새 도메인의 armored 키 사용
# 커널 모듈 = DKMS 빌드 → 빌드 시 커널 헤더 필요
#   DKMS = 커널 교체 시마다 모듈을 자동 재빌드하는 구조
#   설치 대상 = HWE 헤더 메타 + 현재 커널 헤더
#   메타 필요 이유: 커널이 올라가도 재빌드 유지
realsense_sdk() {
    local RS_KEY="${KEYRING_DIR}/librealsenseai.gpg"
    local RS_LIST=/etc/apt/sources.list.d/librealsenseai.list
    local RS_KEY_URL="https://librealsense.realsenseai.com/Debian/librealsenseai.asc"
    local RS_REPO="https://librealsense.realsenseai.com/Debian/apt-repo"

    # 0) 잔존하는 옛 Intel 키/소스 우선 삭제
    #    잔존 시 그 저장소의 NO_PUBKEY 로 아래 첫 apt update 부터 차단
    #    이 파일들 = 이 설치기 산출물 → 재생성됨
    sudo rm -f /etc/apt/sources.list.d/librealsense.list "${KEYRING_DIR}/librealsense.pgp"

    # 1) 사전 도구 + 커널 헤더(DKMS 빌드용: HWE 헤더 메타 + 현재 부팅 커널)
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
#   선행 조건 = SDK 기설치
#   glob 아님, 패키지 이름 명시 → 어느 머신에서도 동일 설치 결과
realsense_ros() {
    sudo apt-get update

    # ROS2 바이너리 패키지 = 전체가 한 snapshot
    #   패키지 간 의존 표기 느슨 → 서로 다른 시점의 패키지 혼재 가능
    #   기설치 diagnostic_updater 가 더 구버전 → realsense2_camera 로드 시 undefined symbol 로 사망
    #   apt = 그 옛 패키지 자동 승급 안 함
    # 대응 = 이미 설치된 ROS 패키지만 현재 snapshot 으로 재정렬
    #   전체 apt upgrade 미사용, ros-${ROS_DISTRO}-* 로 범위 축소
    #   이유: hold 로 고정한 docker/nvidia 버전 불건드림
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
#   컨테이너 미채택 이유: 마이크 = 하드웨어 종속 → 컨테이너로 오디오를 넘기는 방식이 머신마다 깨짐
app_voice() {
    local OWW_SRC="${SCRIPT_DIR}/oww_models"
    local WAKEWORD_MODEL="${VOICE_WS}/resource/hello_rokey_8332_32.tflite"

    # 아래에서 쓰는 ai-edge-litert = Python 3.12 wheel 만 존재 → 다른 버전이면 이 지점에서 즉시 정지
    local PYVER
    PYVER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    if [[ "${PYVER}" != "3.12" ]]; then
        echo "voice: Python 3.12 기대(noble), 실제 ${PYVER} — ai-edge-litert wheel 전제 불충족" >&2
        exit 1
    fi

    # 1) 오디오 시스템 라이브러리
    #    portaudio = PyAudio/sounddevice 소비
    #    libsndfile = soundfile 소비
    #    ffmpeg = 오디오 디코드 소비
    #    -dev = pyaudio 컴파일용
    echo "[voice] 1/6 시스템 라이브러리(apt)"
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends \
        python3-dev python3-pip \
        portaudio19-dev libportaudio2 libsndfile1 libasound2-dev ffmpeg

    # sudo 로 system site-packages 설치 필수 → 모든 셸의 `ros2 run` 이 그대로 인식
    #   non-root pip = ~/.local 행 여부가 버전마다 상이 → 설치 위치 확정 불가
    # Ubuntu = system Python 을 apt 관리 대상으로 보고 pip 설치 차단 → --break-system-packages 로 해제
    local PIP=(sudo python3 -m pip install --break-system-packages --no-cache-dir)

    # 2) 음성/LLM 스택(scipy 1.18+ = numpy>=2 요구 → 마지막의 numpy<2 고정과 충돌 → 상한 설정)
    echo "[voice] 2/6 langchain / openai / 음성 스택"
    # openai = apt 설치본 typing-extensions 승급 시도
    #   dpkg 설치본 = pip 로 삭제 불가("RECORD file not found") → 방치 시 실패
    #   대응: 상위 버전을 먼저 얹어 apt 본을 가림 → 이후 단계는 충족으로 판단, 삭제 미시도
    #   현재 이 방식으로 걸리는 apt 파이썬 패키지 = typing-extensions 뿐(증가 시 여기 한 줄 추가)
    "${PIP[@]}" --ignore-installed --no-deps "typing-extensions>=4.14,<5"
    "${PIP[@]}" \
        "langchain<2" "langchain-openai<2" "openai<3" \
        pyaudio sounddevice "scipy<1.18" python-dotenv

    # 3) openwakeword(호출어 감지)
    #    의존성에 tflite-runtime 포함 + 그 패키지 = 3.12 wheel 없음 → --no-deps 설치
    echo "[voice] 3/6 openwakeword(--no-deps)"
    "${PIP[@]}" --no-deps "openwakeword==0.6.0"

    # 4) 위에서 빠진 실제 의존성 직접 설치(tflite-runtime 자리 = API 동일한 ai-edge-litert 로 대체)
    echo "[voice] 4/6 openwakeword 의존 + ai-edge-litert"
    "${PIP[@]}" \
        "onnxruntime<2,>=1.10.0" "tqdm<5,>=4.0" "scikit-learn<2,>=1" "requests<3,>=2.0" \
        "ai-edge-litert>=2.0.2,<3"
    # openwakeword 코드 = `import tflite_runtime.interpreter` 를 그대로 호출
    #   → 그 이름을 ai_edge_litert 로 잇는 최소 모듈을 site-packages 에 생성
    sudo python3 -c "import os,ai_edge_litert as a; d=os.path.join(os.path.dirname(os.path.dirname(a.__file__)),'tflite_runtime'); os.makedirs(d,exist_ok=True); open(os.path.join(d,'__init__.py'),'w').close(); open(os.path.join(d,'interpreter.py'),'w').write('from ai_edge_litert.interpreter import Interpreter  # noqa: F401\n')"

    # 5) 모델 채우기 = 동봉 모델 복사 → 나머지 모델 다운로드 → 전체 무결성 검증
    #    openwakeword 설치 경로 = root 소유 → 일반 사용자 런타임의 쓰기 불가
    #    → 런타임이 받으려 할 모델을 설치 시점에 선행 배치(기존 파일 skip → 런타임의 다운로드 호출이 무동작)
    #    다운로드 일시 실패 → 에러 HTML 이 .tflite 이름으로 저장 → 런타임에서야 폭발
    #    → 수신 후 파일 시그니처 확인 + 손상본 삭제 + 이 지점에서 정지(재실행 시 재다운로드)
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

    # 6) numpy 1.x 복원
    #    앞의 pip 단계 중 하나가 2.x 를 끌어왔을 가능성 존재
    #    이 스택 검증 범위 = 1.x 뿐
    #    이미 1.x → 무동작
    echo "[voice] 6/6 numpy<2 보장 + import 검증"
    "${PIP[@]}" "numpy<2"

    # 검증
    #   openwakeword = import 만으로 불충분(모델 로드 시점 = 런타임)
    #   → 실제 모델 적재 + 추론 1회까지 수행해야 여기서 실패 검출 가능
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
#   호출 시점 = DSR + RealSense 설치 완료 후 1회
#   앞 단계마다 빌드 → 동일 작업 반복
app_colcon() {
    if [[ ! -d "${DSR_WORKSPACE}/src" ]]; then
        echo "colcon: ${DSR_WORKSPACE}/src missing — the DSR install step must run first" >&2
        exit 1
    fi

    # ROS2 환경 로드(setup.bash = 미정의 변수 참조 → set -u 일시 해제 필요)
    set +u
    # shellcheck disable=SC1090,SC1091
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
    set -u

    # CycloneDDS RMW 패키지 = 빌드 전제 조건
    #   config.sh 가 기본 RMW 를 cyclonedds 로 고정
    #   부재 시 dsr_msgs2 등이 CMake 단계에서 미들웨어 탐색 실패
    #   ROS desktop = Fast-DDS 만 설치 → 별도 패키지인 이것을 여기서 확보
    if ! dpkg -s "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp" >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp"
    fi

    cd "${DSR_WORKSPACE}"

    # rosdep = 워크스페이스 패키지들의 선언 의존성 대리 설치(init = 앞 설치에서 완료)
    rosdep update
    # skip 키 목록
    #   librealsense2 = apt 직접 설치한 네이티브 SDK → rosdep 키 아님
    #   message_generation/message_runtime = 그리퍼 패키지의 ROS1 잔재 → jazzy 에 규칙 없음
    #   미지정 시 사용조차 안 되는 키 때문에 이 단계 전체 실패
    # `-r`(오류 무시 진행) 미사용 이유 = 진짜 누락된 의존성까지 함께 은폐
    rosdep install --from-paths src --ignore-src --rosdistro "${ROS_DISTRO}" \
        --skip-keys="librealsense2 message_generation message_runtime" -y

    # object_detection = host 실행 불가(torch = yolo 이미지 안에만 존재) → 빌드 제외
    # voice_processing = host 에서 그대로 실행 → 여기서 함께 빌드
    colcon build --packages-skip object_detection

    # wakeword 모델의 빌드 산출물(install/) 반영 여부 확인
    #   런타임 탐색 경로 = 소스 트리 아님, 설치된 패키지 경로
    #   앞의 voice 단계 관측 범위 = 소스 트리뿐
    #   → setup.py 가 resource/ 를 설치하지 않는 경우의 유일한 검출 지점 = 여기
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
#   역할 = host 의 드라이버 라이브러리 + GPU 장치를 컨테이너 안으로 주입
#   CUDA 런타임 자체 = 이미 PyTorch wheel 안에 포함
#   부재 시 yolo 컨테이너의 GPU 인식 실패
app_toolkit() {
    local TOOLKIT_LIST=/etc/apt/sources.list.d/nvidia-container-toolkit.list
    local TOOLKIT_KEY="${KEYRING_DIR}/nvidia-container-toolkit.gpg"

    # 0) 사전 조건
    #    드라이버 또는 docker 부재 → 반쪽 설치 진입 없이 즉시 정지
    #    SKIP_IF_NO_GPU=1 → GPU 없는 머신으로 간주 → 에러 아님, 정상 skip 처리
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

    # 2) 키링 + apt source 등록. 설치 직전 update = 아래 3) 담당 → 여기선 --no-update
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

    # 4) docker 에 nvidia runtime 등록(nvidia-ctk = /etc/docker/daemon.json 갱신)
    sudo nvidia-ctk runtime configure --runtime=docker

    # 5) 그 변경 반영 시점 = docker 재시작 후(재시작 = 구동 중 컨테이너 정지 → 사전 동의 수령)
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
