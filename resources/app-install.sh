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

# ROKEY-SPARK fork 를 커밋으로 고정해 clone 하므로 upstream 이 force-push/삭제돼도 흔들리지 않고,
# 에뮬레이터 이미지도 config.sh 의 태그 하나로 고정해 latest 로 조용히 drift 하는 것을 막는다.
app_dsr() {
    local WS_SRC="${DSR_WORKSPACE}/src"
    # 소스는 upstream doosan-robotics/doosan-robot2 가 아니라 ROKEY-SPARK fork 를 쓴다 — upstream 이
    # force-push/삭제해도 살아남고, 호환 패치를 얹을 수 있기 때문. 리비전 핀(DSR_COMMIT)은 config.sh.

    # 1) 워크스페이스 src 디렉토리.
    mkdir -p "${WS_SRC}"

    # 2) doosan-robot2 clone (멱등 — .git 이 있으면 건너뜀).
    if [[ -d "${WS_SRC}/doosan-robot2/.git" ]]; then
        echo "dsr: doosan-robot2 already cloned (skip)"
        # 기존 작업본은 checkout 으로 덮어쓰지 않는다 — 개발 중 변경을 날리지 않기 위함(cobot2 / M0609 와
        # 같은 원칙). 다만 핀과 어긋나면 알린다: 머신마다 다른 리비전으로 빌드되는 상태를 조용히 넘기면
        # "저 머신에선 되는데" 를 추적할 방법이 없어진다.
        DSR_HEAD="$(git -C "${WS_SRC}/doosan-robot2" rev-parse HEAD)"
        if [[ "${DSR_HEAD}" != "${DSR_COMMIT}" ]]; then
            echo "dsr: warning — 기존 clone 이 핀과 다름 (${DSR_HEAD:0:8} != ${DSR_COMMIT:0:8})" >&2
            echo "dsr:           핀에 맞추려면: git -C ${WS_SRC}/doosan-robot2 checkout --detach ${DSR_COMMIT}" >&2
        fi
    else
        # fork 에는 'jazzy' 브랜치가 없으므로 -b "${DSR_BRANCH}" 를 주면 안 됨("Remote branch not found").
        # 기본 브랜치로 받은 뒤 핀 커밋으로 detach — fork main 에 커밋이 얹혀도 설치 결과가 안 흔들린다.
        git clone "${DSR_REPO_URL}" "${WS_SRC}/doosan-robot2"
        git -C "${WS_SRC}/doosan-robot2" checkout --detach "${DSR_COMMIT}"
    fi

    # DSR_ROBOT2.py 호환 패치(서비스 클래스명 SetSingular[ity]HandlingForce, _srv_name_prefix)는
    # 여기서 sed 로 하지 않는다 — fork 커밋 f1118a1 이 이미 반영본이라 이 스크립트의 패치는 항상 no-op 였다.

    # cobot2 앱 소스는 여기에 미러링 안 함 — 이 레포는 더 이상 미제공. 사용자가
    # ${WS_SRC}/cobot2 에 직접 배치; setup-app.sh 가 colcon-build.sh 를 부르기 전에 존재 확인(없으면 곧바로 실패).

    # 3) DSR 빌드에 필요한 apt 패키지 (a01 ros2-install.sh / desktop core 에 없는 DSR 전용 것만).
    #    나머지 선언적(declarative) 의존성은 colcon-build.sh 의 rosdep install 이 자동 해결.
    sudo apt-get update
    sudo apt-get install -y \
        "ros-${ROS_DISTRO}-velocity-controllers" \
        "ros-${ROS_DISTRO}-eigen3-cmake-module"

    # 3b) robot_control(host 클라이언트)의 런타임 Python 의존성 — 얇은 클라이언트라 system Python(apt)으로 설치.
    #     이건 컨테이너 방식이라 앱 Python(torch/ultralytics/openwakeword)의 집은 yolo/voice 컨테이너지만,
    #     robot_control 은 host 에서 도는 ROS2 노드라 scipy(좌표 변환)/numpy/pymodbus(그리퍼 Modbus 통신)는
    #     host 에 있어야 함. ament_python 은 빌드할 때 import 하지 않아 colcon 은 통과하지만, ros2 run 은 런타임에 깨짐.
    #     venv 대신 apt 를 쓰는 이유: host=system Python 책임을 지키고, 별도 activation 없이 ros2 run 이 이 패키지들을 보게 함.
    #     noble apt 의 numpy(1.26, <2)면 충분(host 엔 ultralytics 없음); noble apt 의 pymodbus 는 3.x
    #     (onrobot.py 를 3.x API 로 마이그레이션함).
    sudo apt-get install -y \
        python3-numpy python3-scipy python3-pymodbus

    # 4) DSR 에뮬레이터 이미지 (명시 태그 — 이미 있으면 docker 가 자동으로 건너뜀).
    docker pull "doosanrobot/dsr_emulator:${DSR_EMULATOR_VERSION}"

    echo "dsr: success installing Doosan DSR (${DSR_BRANCH}) + emulator ${DSR_EMULATOR_VERSION}"
}

#######################################
# librealsense2 SDK(DKMS 커널 모듈 + 유틸 + 헤더) 설치. apt repo·키링 등록 포함.
# Globals:
#   KEYRING_DIR, KERNEL_HEADERS_META, UBUNTU_CODENAME (읽기)
# Outputs:
#   성공 시 요약 한 줄을 stdout 으로 출력.
#######################################
# 배경/이유:
#   - 2025-11 에 RealSense 가 Intel 에서 분사(spin-off)해 RealSense AI 가 되며 apt repo 도메인과 서명 키가 함께 바뀜.
#     옛 librealsense.intel.com/.../librealsense.pgp 는 2018 년 Intel 키(C8B3A55A...)를 주지만, noble repo 는
#     새 키(...FB0B24895113F120, @realsenseai.com)로 서명돼 있어 옛 키로는 검증 실패(NO_PUBKEY).
#     현재 공식 방법(librealsense/doc/distribution_linux.md) = realsenseai.com 도메인 + .asc(armored) 키를
#     gpg --dearmor 로 변환(dearmor = armored 텍스트 키를 바이너리 GPG 키로 변환).
#   - 키링은 ${KEYRING_DIR}/librealsenseai.gpg + signed-by 로 지정(deprecated 된 apt-key 미사용).
#   - repo codename 은 `lsb_release -cs` 대신 ${UBUNTU_CODENAME}(config 단일 소스) 사용.
#   - DKMS 커널 모듈 빌드에는 커널 헤더가 필요 → HWE 커널(Ubuntu 하드웨어 지원 커널) 헤더 메타(${KERNEL_HEADERS_META})와
#     현재 커널 헤더를 함께 설치. 메타가 있으면 커널 업데이트 뒤에도 헤더가 자동으로 따라와서 librealsense2-dkms
#     재빌드가 깨지지 않음(헤더가 없으면 카메라 커널 모듈 빌드 실패).
#   - 제거됨: `apt remove --purge libgtk-3-dev`(되돌릴 수 없는 purge, noble 에선 불필요),
#              `realsense-viewer` 자동 실행(GUI 가 떠서 진행이 막힘).
realsense_sdk() {
    local RS_KEY="${KEYRING_DIR}/librealsenseai.gpg"
    local RS_LIST=/etc/apt/sources.list.d/librealsenseai.list
    local RS_KEY_URL="https://librealsense.realsenseai.com/Debian/librealsenseai.asc"
    local RS_REPO="https://librealsense.realsenseai.com/Debian/apt-repo"

    # 0) 분사(spin-off) 이전 Intel 키/소스가 남아 있으면 제거 — apt-get update 전에 안 지우면
    #    옛 repo 의 NO_PUBKEY 때문에 첫 update 가 막힘. 이 파일은 이 프로젝트가 만든 산출물이라 다시 생성 가능.
    sudo rm -f /etc/apt/sources.list.d/librealsense.list "${KEYRING_DIR}/librealsense.pgp"

    # 1) 사전 도구 + 키링 디렉터리 + 커널 헤더(DKMS 빌드용 — HWE 커널 헤더 메타 + 현재 커널).
    sudo apt-get update
    sudo apt-get install -y curl ca-certificates gnupg apt-transport-https \
        "${KERNEL_HEADERS_META}" "linux-headers-$(uname -r)"
    # 2) 키링 + apt 소스(add_apt_repo — armored 키를 dearmor 변환, 멱등(여러 번 실행해도 결과 동일)).
    add_apt_repo \
        --mode dearmor --downloader curl-sSf --key-write tee \
        --key-url "${RS_KEY_URL}" --key-file "${RS_KEY}" \
        --list-file "${RS_LIST}" \
        --list-line "deb [signed-by=${RS_KEY}] ${RS_REPO} ${UBUNTU_CODENAME} main"

    # 4) librealsense2 SDK(커널 DKMS 모듈 + 유틸 + 헤더 + 디버그 심볼).
    sudo apt-get install -y \
        librealsense2-dkms \
        librealsense2-utils \
        librealsense2-dev \
        librealsense2-dbg

    echo "realsense-sdk: success installing RealSense librealsense2 SDK (${UBUNTU_CODENAME} apt repo)"
}

#######################################
# ROS2 realsense2 wrapper 패키지(camera + description) 설치. SDK 가 먼저 설치돼 있다고 가정.
# Globals:
#   ROS_DISTRO (읽기)
# Outputs:
#   성공 시 요약 한 줄을 stdout 으로 출력.
#######################################
# 배경/이유:
#   - ros-humble-realsense2-* → ros-${ROS_DISTRO}-realsense2-* 로 옮김.
#   - 원래의 glob(`ros-humble-realsense2-*`) 대신 패키지를 명시 — 설치 결과가 항상 같도록(deterministic).
#     camera 는 realsense2-camera-msgs 를 의존성으로 함께 끌어옴.
#   - rosdep init/update + colcon build 는 a02 의 colcon-build.sh 로 옮겨 중복 제거.
realsense_ros() {
    sudo apt-get update

    # ROS2 바이너리 패키지들은 하나의 동기화된 snapshot 을 이룸. 패키지 간 의존이 느슨하고(loose) SONAME 도
    # 안 올라가서, 서로 다른 snapshot 을 섞으면 dlopen 시점에 ABI 가 깨짐. 그러면 realsense2_camera 가
    # undefined symbol(diagnostic_updater::Updater::Updater(NodeBaseInterface, ... , double, uint8))로 죽음 —
    # 이미 깔린 diagnostic_updater 가 realsense2_camera snapshot 보다 오래된 경우. 의존이 느슨해서 apt 가
    # 이미 설치된 옛 diagnostic_updater 를 자동으로 올려주지 않기 때문. 그래서 먼저 설치된 ROS 패키지들을 현재
    # snapshot 으로 다시 맞춰(re-sync), realsense 가 요구하는 ABI 의존을 wrapper 가 빌드된 버전과 일치시킴.
    # 범위를 ros-${ROS_DISTRO}-* 네임스페이스로 일부러 한정: 여기서 전체 `apt upgrade` 는 피함(hold 로 잡아둔
    # docker/nvidia 핀(버전 고정)을 흔들기 때문). 그 패키지들은 이 glob 밖이고 어차피 hold 돼 있어 핀 안전(pin-safe).
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

# 마이크가 하드웨어에 종속돼 컨테이너 오디오 전달이 머신마다 깨지므로 voice 스택은 컨테이너 대신 host 에
# 직접 깐다 — apt 로 되는 system C 라이브러리는 apt, apt 미제공 스택만 pip(PEP 668 우회 --break-system-packages).
app_voice() {
    local OWW_SRC="${SCRIPT_DIR}/oww_models"
    local WAKEWORD_MODEL="${VOICE_WS}/resource/hello_rokey_8332_32.tflite"

    # Python 3.12 단언 — ai-edge-litert(openwakeword tflite 대체)의 cp312 wheel 전제. fail-loud.
    local PYVER
    PYVER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    if [[ "${PYVER}" != "3.12" ]]; then
        echo "voice-host-install: Python 3.12 기대(noble), 실제 ${PYVER} — ai-edge-litert wheel 전제 불충족" >&2
        exit 1
    fi

    # 1) 시스템 라이브러리(apt — 멱등: 이미 설치면 no-op).
    #    portaudio = PyAudio·sounddevice, libsndfile = scipy/soundfile, ffmpeg = 오디오 디코드.
    #    (-dev 는 pyaudio 컴파일용. numpy 는 dsr-project-install.sh 가 apt python3-numpy 로 이미 설치.)
    echo "[voice-host-install] 1/6 시스템 라이브러리(apt)"
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends \
        python3-dev python3-pip \
        portaudio19-dev libportaudio2 libsndfile1 libasound2-dev ffmpeg

    # system pip(--break-system-packages: PEP 668 externally-managed 우회). sudo = system site-packages 에
    # 설치 → 모든 셸의 `ros2 run`(system python)이 봄. non-root pip 는 버전별로 ~/.local 폴백 여부가 갈려
    # 예측 불가 → sudo 로 설치 위치 확정. apt numpy 등 이미 만족하는 핀은 pip 가 no-op(dpkg 파일 미클로버).
    local PIP=(sudo python3 -m pip install --break-system-packages --no-cache-dir)

    # 2) 음성/LLM 스택(voice 컨테이너 핀 미러링). scipy 는 1.18 부터 런타임이 numpy>=2 를 요구(np.long)
    #    → 마지막 numpy<2 재핀과 충돌하므로 <1.18 로 상한.
    echo "[voice-host-install] 2/6 langchain / openai / 음성 스택"
    # openai(>=4.14)가 apt 설치본 python3-typing-extensions(4.10)를 업그레이드하려 하지만 dpkg 설치분은
    # RECORD 파일이 없어 pip uninstall 이 실패한다("Cannot uninstall typing_extensions ... RECORD file not
    # found. Hint: installed by debian"). --ignore-installed --no-deps 로 상위본을 /usr/local(sys.path 우선)에
    # 먼저 얹어 apt 본을 shadow → 이후 스텝은 이미 충족으로 보고 uninstall 시도 자체를 안 한다.
    # ponytail: 지금 apt 파이썬 패키지 중 pip 상향이 필요한 건 typing-extensions 뿐. 다른 게 같은 식으로
    #           걸리면(같은 RECORD 에러) 그 패키지도 여기에 한 줄 추가.
    "${PIP[@]}" --ignore-installed --no-deps "typing-extensions>=4.14,<5"
    "${PIP[@]}" \
        "langchain<2" "langchain-openai<2" "openai<3" \
        pyaudio sounddevice "scipy<1.18" python-dotenv

    # 3) openwakeword 0.6.0 — 의존으로 tflite-runtime(3.12 wheel 없음)을 강제 → --no-deps 로 설치.
    echo "[voice-host-install] 3/6 openwakeword(--no-deps)"
    "${PIP[@]}" --no-deps "openwakeword==0.6.0"

    # 4) openwakeword 실제 의존 명시 설치 + tflite-runtime 자리에 ai-edge-litert(cp312 wheel, 동일 API).
    echo "[voice-host-install] 4/6 openwakeword 의존 + ai-edge-litert"
    "${PIP[@]}" \
        "onnxruntime<2,>=1.10.0" "tqdm<5,>=4.0" "scikit-learn<2,>=1" "requests<3,>=2.0" \
        "ai-edge-litert>=2.0.2,<3"
    # openwakeword 코드는 `import tflite_runtime.interpreter` 를 하드 호출 → ai_edge_litert 로 잇는 최소 shim
    # 을 site-packages 에 생성(root 소유 system site-packages 에 쓰므로 sudo. 위치는 ai_edge_litert 에서 동적 해석).
    sudo python3 -c "import os,ai_edge_litert as a; d=os.path.join(os.path.dirname(os.path.dirname(a.__file__)),'tflite_runtime'); os.makedirs(d,exist_ok=True); open(os.path.join(d,'__init__.py'),'w').close(); open(os.path.join(d,'interpreter.py'),'w').write('from ai_edge_litert.interpreter import Interpreter  # noqa: F401\n')"

    # 5) 모델 provisioning: bundled feature 모델 복사 → stock wakeword 모델 다운로드 → 전체 TFL3 검증.
    #    feature(melspec/embedding/VAD)는 wheel 미동봉 → 동봉본(resources/oww_models)을 openwakeword 설치
    #    경로로 복사(네트워크 우회, 동봉본 authoritative). stock 모델(alexa 등)은 corecode 튜토리얼이 런타임에
    #    openwakeword.utils.download_models() 로 받는데, 이 경로가 sudo 설치라 root 소유 → 비-root 런타임이
    #    write 못 함(PermissionError). 설치 때 root 로 미리 받아 채우면 download_models 는 존재-가드라 이미 있는
    #    파일을 skip → 런타임 호출이 no-op 이 되어 권한 오류가 사라진다. 과거 download_models 는 transient 504 시
    #    에러 HTML 을 .tflite 로 저장해 런타임 크래시 → 받은 뒤 'TFL3' 매직(offset 4)을 검증하고 손상본은 삭제 후
    #    중단(fail-loud) → 재실행 시 재다운로드로 자가치유(손상본이 존재-가드에 걸려 영구 캐시되는 poison-pill 차단).
    echo "[voice-host-install] 5/6 feature 복사 + stock 모델 다운로드 + TFL3 검증"
    # root 소유 openwakeword 경로에 쓰므로 sudo. sudo 는 env 를 지우므로 OWW_SRC 는 `env` 로 전달.
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

    # 6) numpy<2 보장(검증본 규율). 이미 <2(apt python3-numpy 1.26)면 pip 가 no-op → apt 패키지 클로버 안 함.
    #    pip 스텝 중 하나가 numpy>=2 를 끌어왔으면 여기서 다운핀. force-reinstall 은 쓰지 않음(불필요 클로버 방지).
    echo "[voice-host-install] 6/6 numpy<2 보장 + import 검증"
    "${PIP[@]}" "numpy<2"

    # import 검증 게이트 — openwakeword 는 import 만으론 부족(런타임에만 .tflite 로드)하므로
    # 실제 wakeword 모델을 Model 로 인스턴스화 + predict 1회까지 확증(fail-loud).
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

# DSR/RealSense 설치가 끝난 뒤 딱 한 번만 빌드해 중복 빌드를 막고, 컨테이너 전용 object_detection 은
# --packages-skip 으로 건너뛰어 host 에 없는 torch 의존을 피한다.
app_colcon() {
    if [[ ! -d "${DSR_WORKSPACE}/src" ]]; then
        echo "colcon-build: ${DSR_WORKSPACE}/src missing — the DSR install step must run first" >&2
        exit 1
    fi

    # ROS2 환경 로드 (set -u 상태에서 setup.bash 가 미정의 변수(unbound var)로 터지는 문제 회피).
    set +u
    # shellcheck disable=SC1090,SC1091
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
    set -u

    # CycloneDDS RMW(ROS 미들웨어 구현) 패키지 반드시 깔아 둠 — config.sh 가 기본 RMW 를 cyclonedds 로 핀(고정)해
    # 둠 → colcon 이 패키지의 기본 RMW 를 찾을 때 rmw_cyclonedds_cpp 설치돼 있어야 함 (없으면 dsr_msgs2 등이
    # CMake configure 단계에서 "Could not find ROS middleware implementation 'rmw_cyclonedds_cpp'" 로 실패).
    # ROS desktop 은 fastrtps 만 깔고 cyclonedds 는 별도 패키지 → 빌드 전제 조건으로 여기서 설치.
    # 이미 깔려 있으면 dpkg 로 확인해 apt 를 통째로 건너뜀 (멱등 + 재개 시 네트워크 불필요).
    if ! dpkg -s "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp" >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp"
    fi

    cd "${DSR_WORKSPACE}"

    # rosdep: 워크스페이스 패키지들이 선언해 둔 의존성을 자동 설치 (init 은 a01 에서 이미 끝냄).
    rosdep update
    # skip-keys 사유:
    #   librealsense2                      — apt 로 까는 네이티브 SDK. ROS rosdep 키가 아니다.
    #   message_generation/message_runtime — onrobot_rg_control/package.xml 의 ROS1 잔재. jazzy 에 해당
    #                                        rosdep 규칙이 없어 그대로 두면 이 단계가 통째로 실패한다
    #                                        (이 스크립트는 set -e). 실제 빌드에는 쓰이지 않는 키다.
    # `-r`(오류 무시하고 계속)은 쓰지 않는다 — 모든 해결 실패를 삼켜 진짜 누락 의존까지 가린다.
    rosdep install --from-paths src --ignore-src --rosdistro "${ROS_DISTRO}" \
        --skip-keys="librealsense2 message_generation message_runtime" -y

    # colcon 빌드. object_detection(yolo)은 host 에서 실행 불가(torch 가 yolo 이미지 안에만) → --packages-skip.
    # voice_processing 은 host 직접 실행이라 여기서 빌드(voice-host-install.sh 가 langchain/openwakeword 를
    # host 에 깔아 둠 → console_script 의 system python 이 그대로 봄).
    colcon build --packages-skip object_detection

    # wakeword 모델이 설치 트리(install/)에 들어갔는지 확인.
    # 런타임의 voice_processing 은 모델을 get_package_share_directory() 로 찾는다 — 소스 트리가 아니다.
    # voice-host-install.sh 의 검증 게이트는 이 빌드보다 먼저 돌기 때문에 소스 경로만 볼 수 있다.
    # 그래서 setup.py 의 data_files 가 resource/ 를 설치하지 않는 경우를 여기서만 잡을 수 있다.
    # 안 잡으면 첫 `ros2 run voice_processing get_keyword` 에서야 드러난다.
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

# 컨테이너 안 CUDA 런타임은 PyTorch wheel 에 이미 포함돼 있으므로, 이 toolkit 은 host 드라이버
# 라이브러리와 /dev/nvidia* 장치를 컨테이너에 주입하는 역할만 한다 — 없으면 yolo 컨테이너가 GPU 를 못 잡는다.
app_toolkit() {
    local TOOLKIT_LIST=/etc/apt/sources.list.d/nvidia-container-toolkit.list
    local TOOLKIT_KEY="${KEYRING_DIR}/nvidia-container-toolkit.gpg"

    # 0) 사전 조건 확인 — 드라이버·docker 없으면 크게 실패(fail-loud — 조용히 넘어가지 않고 바로 에러로 멈춰 반쪽 설치 방지).
    #    SKIP_IF_NO_GPU=1 (install.sh 통합 흐름): GPU 없는 host 전용 머신 = toolkit 불필요 →
    #    드라이버 없어도 에러 아닌 정상 skip 으로 취급(단계 = DONE 표시). 단독 실행 기본값 = fail-loud.
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

    # 2) 키링 + apt source 등록 (add_apt_repo — 원본 list 를 받아 signed-by 를 끼워 넣고, cat 으로 여러 줄 비교).
    #    설치 직전 update 는 아래 3) 에서 하므로 여기선 --no-update.
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

    # 4) docker runtime 등록 (멱등 — nvidia-ctk 가 /etc/docker/daemon.json 갱신).
    sudo nvidia-ctk runtime configure --runtime=docker

    # 5) runtime 적용 — daemon.json 변경 = docker 재시작 후에야 반영. 이미 적용돼 있으면 재시작 skip.
    #    docker 데몬 재시작 = 되돌릴 수 없는 작업 → 명시적 동의 필요(ASSUME_YES=1 로 자동화 가능).
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
