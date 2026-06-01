#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/host-python-deps.sh — host application Python 설치 (application-shell variant, a02 step).
#
# 본 브랜치는 컨테이너 없이 host 단독 실행(monolith)이다. cobot2_ws 의 host 실행 패키지
# (robot_control / pick_and_place_* / voice_processing / object_detection)가 런타임에 import 하는
# application Python(torch / torchvision / ultralytics / opencv / openwakeword / langchain / openai /
# pymodbus 등)을 host 에 설치한다. ament_python 은 빌드시 import 하지 않으므로 colcon 빌드는 이게
# 없어도 통과하지만, `ros2 run` 런타임에 ModuleNotFoundError 가 난다 — 그 격차를 메운다.
#
# PEP 668(noble externally-managed) 회피: system Python 전역 pip 대신 venv(--system-site-packages,
# rclpy/colcon 가시)에 설치. 핀은 Phase 4 컨테이너 Dockerfile(검증본)을 미러링한다(docs/COMPATIBILITY.md).
# 순수 설치 본문 — state 호출 없음(a02 오케스트레이터가 step 프레이밍 소유).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Python 3.12 단언 — ai-edge-litert(openwakeword tflite 대체)의 cp312 wheel 전제. fail-loud.
PYVER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
if [[ "${PYVER}" != "3.12" ]]; then
    echo "host-python-deps: Python 3.12 기대(noble), 실제 ${PYVER} — ai-edge-litert wheel 전제 불충족" >&2
    exit 1
fi

# 1) 시스템 라이브러리 (apt — 멱등: 이미 설치면 no-op).
#    portaudio/asound = PyAudio·sounddevice, libsndfile = scipy/soundfile, ffmpeg = ultralytics,
#    libgl1 = opencv-python(cv2) 런타임. (-dev 이미지 라이브러리는 wheel 사용이라 불요.)
echo "[host-python-deps] 1/6 시스템 라이브러리 (apt)"
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    python3-dev python3-venv python3-pip \
    portaudio19-dev libportaudio2 libsndfile1 libasound2-dev \
    ffmpeg libgl1

# 2) venv (--system-site-packages: venv 안에서 rclpy/colcon 가시). 없을 때만 생성(멱등).
echo "[host-python-deps] 2/6 venv (${HOST_VENV})"
if [[ ! -d "${HOST_VENV}" ]]; then
    python3 -m venv --system-site-packages "${HOST_VENV}"
fi
VPIP="${HOST_VENV}/bin/pip"
VPY="${HOST_VENV}/bin/python"
"${VPIP}" install --no-cache-dir --upgrade pip

# 3) YOLO/로봇 스택 (yolo 컨테이너 핀 미러링). torch cu${CUDA_VERSION} wheel 이 CUDA 런타임을
#    번들 → host CUDA toolkit 불요(GPU 는 드라이버 경유). pymodbus 는 3.x(onrobot.py 가 3.x API).
echo "[host-python-deps] 3/6 torch(cu${CUDA_VERSION//./}) + ultralytics + opencv + pymodbus"
"${VPIP}" install --no-cache-dir \
    --index-url "https://download.pytorch.org/whl/cu${CUDA_VERSION//./}" \
    torch torchvision
"${VPIP}" install --no-cache-dir \
    "ultralytics<9" "opencv-python<4.10" supervision \
    "pymodbus<4"

# 4) 음성/LLM 스택 (voice 컨테이너 핀 미러링).
echo "[host-python-deps] 4/6 langchain / openai / 음성 스택"
"${VPIP}" install --no-cache-dir \
    "langchain<2" "langchain-openai<2" "openai<3" \
    pyaudio sounddevice "scipy<2" python-dotenv

# 5) openwakeword 0.6.0 — wakeword 모델이 .tflite 라 tflite 백엔드 필요. 0.6.0 은 tflite-runtime(>=2.8)
#    을 의존으로 강제하나 tflite-runtime 은 Python 3.12 wheel 이 없다(최대 3.11). 따라서 --no-deps 로
#    설치하고, 실제 의존을 명시하되 tflite-runtime 자리에 후속작 ai-edge-litert(cp312 wheel, 동일
#    Interpreter API)를 넣는다. openwakeword 코드는 `import tflite_runtime.interpreter` 를 하드 호출하므로
#    ai_edge_litert 로 잇는 최소 shim 을 site-packages 에 생성. feature 모델(melspec/embedding/VAD)은
#    wheel 미동봉 → download_models 로 받는다(커스텀 wakeword 라 공식 사전학습 모델은 더미명으로 skip).
echo "[host-python-deps] 5/6 openwakeword + ai-edge-litert(tflite 대체) + shim"
"${VPIP}" install --no-cache-dir --no-deps "openwakeword==0.6.0"
"${VPIP}" install --no-cache-dir \
    "onnxruntime<2,>=1.10.0" "tqdm<5,>=4.0" "scikit-learn<2,>=1" "requests<3,>=2.0" \
    "ai-edge-litert>=2.0.2,<3"
"${VPY}" -c "import os,ai_edge_litert as a; d=os.path.join(os.path.dirname(os.path.dirname(a.__file__)),'tflite_runtime'); os.makedirs(d,exist_ok=True); open(os.path.join(d,'__init__.py'),'w').close(); open(os.path.join(d,'interpreter.py'),'w').write('from ai_edge_litert.interpreter import Interpreter  # noqa: F401\n')"
"${VPY}" -c "import openwakeword.utils as u; u.download_models(['__feature_only__'])"

# 6) numpy<2 마지막 재핀 (ultralytics 호환 — 필수). torch/ultralytics/scikit-learn 이 numpy>=2 를
#    끌어왔을 수 있어 강제 다운핀 후 import 검증으로 확증.
echo "[host-python-deps] 6/6 numpy<2 재핀 + import 검증"
"${VPIP}" install --no-cache-dir --force-reinstall "numpy<2"

# import 검증 게이트 — host 토폴로지(yolo+voice+robot) 합집합. openwakeword 는 import 만으론
# 부족하므로(런타임에만 .tflite 로드) Model(.tflite) 인스턴스화 + predict 1회까지 확증(fail-loud).
OWW_MODEL="${REPO_DIR}/cobot2_ws/voice_processing/resource/hello_rokey_8332_32.tflite" \
"${VPY}" - <<'PY'
import os, numpy as np
import numpy, scipy, cv2, ultralytics, supervision, sklearn, pymodbus, torch
from scipy.spatial.transform import Rotation  # noqa: F401  robot_control 좌표 변환
import langchain, langchain_openai, openai, pyaudio, sounddevice  # noqa: F401
import openwakeword, ai_edge_litert, tflite_runtime.interpreter, dotenv  # noqa: F401
assert numpy.__version__.startswith("1."), numpy.__version__
from openwakeword.model import Model
m = Model(wakeword_models=[os.environ["OWW_MODEL"]])
m.predict(np.zeros(1280, dtype=np.int16))
print(f"  host-python-deps import OK — numpy {numpy.__version__}, torch {torch.__version__}, "
      f"tflite shim -> {tflite_runtime.interpreter.Interpreter.__module__}, openwakeword Model(.tflite) load OK")
PY

echo "success installing host application Python at ${HOST_VENV}"
