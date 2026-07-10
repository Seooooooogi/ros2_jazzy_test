#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/voice-host-install.sh — voice_processing 노드의 host application Python 을 직접 설치.
#
# voice 는 컨테이너가 아니라 host 에서 실행한다(마이크가 하드웨어 종속이라 컨테이너 오디오
# passthrough 가 머신마다 깨짐 — ADR-027). langchain / openai(Whisper STT) / openwakeword(wakeword)
# 스택을 host 에 깔아, colcon 이 만든 console_script(system python shebang)의 `ros2 run
# voice_processing get_keyword` 이 이 패키지들을 그대로 보게 한다.
#
# 핀은 검증본을 미러링: backup/voice-processing/Dockerfile(폐기된 컨테이너 레시피) + scripts/venv-demo/LAB.md(Part A4).
# noble 은 PEP 668(externally-managed) 이라 system pip 는 --break-system-packages 필요.
# apt 로 되는 system C 라이브러리는 apt, apt 미제공 스택만 pip.
#   - openwakeword 0.6.0 은 tflite-runtime(Python 3.12 wheel 없음)을 의존으로 강제 → --no-deps 로 깔고
#     후속작 ai-edge-litert(cp312 wheel, 동일 Interpreter API)를 tflite_runtime shim 으로 연결.
#   - feature 모델(melspec/embedding/VAD)은 wheel 미동봉 → resources/oww_models/ 동봉본 복사 + TFL3 검증.
#   - numpy<2 는 항상 마지막(ultralytics 는 없지만 검증본 핀 규율 유지 — scipy<1.18 과 짝).
# 순수 설치 본문 — state 함수 호출 안 함(setup-app.sh 오케스트레이터가 step 프레이밍 소유).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

OWW_SRC="${SCRIPT_DIR}/oww_models"
WAKEWORD_MODEL="${VOICE_WS}/voice_processing/resource/hello_rokey_8332_32.tflite"

# Python 3.12 단언 — ai-edge-litert(openwakeword tflite 대체)의 cp312 wheel 전제. fail-loud.
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
PIP=(sudo python3 -m pip install --break-system-packages --no-cache-dir)

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
