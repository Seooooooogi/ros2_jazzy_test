#!/usr/bin/env bash
# scripts/venv-demo/uv/setup.sh — 데모 venv(~/cobot_venv_ws/.venv) 원커맨드 구성/복구.
# LAB.md A3+A4 와 동일 결과물을 uv.lock 기준으로 재현한다(순서 함정 없음).
# 학습용이 아니다 — 처음이면 LAB.md 를 한 줄씩(각 핀의 이유가 실습 내용).
# exit code 는 0(성공)/비0(실패) 2단계만 — set -e 가 하위 도구(apt/curl/uv) 코드를 그대로 전파한다.
set -euo pipefail

UV_VERSION="0.11.2"
VENV_DIR="$HOME/cobot_venv_ws/.venv"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
TOTAL=6

step() { echo "[$1/${TOTAL}] $2"; }
fail() { echo "venv-uv: [FAIL] $*" >&2; exit 1; }

step 1 "전제 확인 (python3.12 / uv)"
command -v /usr/bin/python3.12 >/dev/null 2>&1 \
    || fail "/usr/bin/python3.12 없음 — Ubuntu 24.04 base 설치(install.sh) 선행 필요"
if ! command -v uv >/dev/null 2>&1; then
    read -rp "venv-uv: uv ${UV_VERSION} 을 설치합니다 (astral.sh installer). 진행? [y/N] " ans
    [[ "${ans}" == [yY]* ]] || fail "uv 미설치 — 중단"
    curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh
    export PATH="$HOME/.local/bin:$PATH"
    command -v uv >/dev/null 2>&1 || fail "uv 설치 후에도 PATH 에 없음 — 셸 재시작 후 재실행"
fi
# 버전 불일치는 경고만 — --frozen 이 lock 재해석을 막아 결과 동일성은 lock 이 보장(강제 중단은 복구 UX 저해).
if [[ "$(uv --version | awk '{print $2}')" != "${UV_VERSION}" ]]; then
    echo "venv-uv: [WARN] uv $(uv --version | awk '{print $2}') ≠ 검증 버전 ${UV_VERSION} — 계속 진행(lock 은 --frozen 이라 해석 고정)" >&2
fi

step 2 "apt 헤더 (portaudio19-dev libsndfile1 python3.12-venv)"
if ! dpkg -s portaudio19-dev libsndfile1 python3.12-venv >/dev/null 2>&1; then
    sudo apt-get install -y portaudio19-dev libsndfile1 python3.12-venv
else
    echo "venv-uv: apt 헤더 이미 설치됨 — skip"
fi

step 3 "venv 생성 (${VENV_DIR}, system-site-packages)"
if [[ -f "${VENV_DIR}/bin/python" ]]; then
    # 플래그 없는 기존 venv 는 sync 까지 통과하고 ROS 바인딩(rclpy)에서만 깨진다 — 재사용 전 확인.
    grep -q '^include-system-site-packages = true$' "${VENV_DIR}/pyvenv.cfg" \
        || fail "기존 venv 가 system-site-packages 없이 생성됨 — rm -rf ${VENV_DIR} 후 재실행"
    echo "venv-uv: venv 이미 존재 — 재사용"
else
    uv venv --python /usr/bin/python3.12 --system-site-packages "${VENV_DIR}"
fi

step 4 "의존성 설치 (uv sync --frozen — torch 포함, 최초 실행은 수 GB 다운로드)"
VIRTUAL_ENV="${VENV_DIR}" uv sync --frozen --active --project "${SCRIPT_DIR}"

PY="${VENV_DIR}/bin/python"

step 5 "post-install (tflite shim / oww feature 모델 / TFL3 검증)"
# tflite_runtime 호환 shim — openwakeword 가 tflite_runtime.interpreter 이름으로 import (LAB A4 (5) 동일)
"${PY}" - <<'EOF'
import os, ai_edge_litert as a
d = os.path.join(os.path.dirname(os.path.dirname(a.__file__)), 'tflite_runtime')
os.makedirs(d, exist_ok=True)
open(os.path.join(d, '__init__.py'), 'w').close()
open(os.path.join(d, 'interpreter.py'), 'w').write('from ai_edge_litert.interpreter import Interpreter  # noqa: F401\n')
EOF
OWW_DIR="$("${PY}" -c 'import os,openwakeword;print(os.path.join(os.path.dirname(openwakeword.__file__),"resources","models"))')"
mkdir -p "${OWW_DIR}"
cp "${REPO_ROOT}"/resources/oww_models/* "${OWW_DIR}"/
# TFL3 매직바이트 + 파일 0개 가드(LAB 명시 함정: 0개면 검사 자체가 공회전)
"${PY}" - "${OWW_DIR}" <<'EOF'
import os, sys
d = sys.argv[1]
files = [f for f in os.listdir(d) if f.endswith('.tflite')]
assert files, 'oww feature 모델 0개 — resources/oww_models/ 확인'
for f in files:
    assert open(os.path.join(d, f), 'rb').read(8)[4:8] == b'TFL3', 'corrupt tflite: ' + f
print('feature models TFL3 OK (%d)' % len(files))
EOF

step 6 "self-check (import 세트 + wakeword 실추론 게이트)"
# LAB A4 검증 블록과 동일 import 세트
"${PY}" - <<'EOF'
import numpy,torch,ultralytics,cv2,langchain,langchain_openai,openai
import pyaudio,sounddevice,scipy,openwakeword,ai_edge_litert
import tflite_runtime.interpreter,pymodbus,roboflow
assert numpy.__version__.startswith('1.'), numpy.__version__
print('deps OK', numpy.__version__)
EOF
# 진짜 게이트(LAB 동일): 의존성·shim·feature 모델·wakeword 모델을 실추론 1회로 한꺼번에 확증.
# ws 미구성(복구 전 단계)이면 skip — venv 자체는 완성.
WAKEWORD="$HOME/cobot_venv_ws/src/pick_and_place_voice/resource/hello_rokey_8332_32.tflite"
if [[ -f "${WAKEWORD}" ]]; then
    "${PY}" - "${WAKEWORD}" <<'EOF'
import sys
import numpy as np
from openwakeword.model import Model
m = Model(wakeword_models=[sys.argv[1]])
m.predict(np.zeros(1280, dtype=np.int16))
print('wakeword gate OK — Model(.tflite) load + predict')
EOF
else
    echo "venv-uv: [SKIP] wakeword gate — ${WAKEWORD} 없음(ws 미구성). venv 는 완성" >&2
fi

echo "venv-uv: success — source ${VENV_DIR}/bin/activate 후 LAB.md Part B 로"
