# pick & place 실습 — 컨테이너 없이 venv 로 실행하기

## 이게 뭔가
- 같은 pick & place 기능을 **두 가지 방식**으로 본다:
  - **컨테이너 방식(정식)**: `bash ~/ros2_jazzy_test/containers/bringup.sh` + `docker compose up -d` — 몇 줄로 끝.
  - **venv 방식(이 문서)**: 모놀리식 노드를 host venv 로 직접 — 의존성 설치·핀·네임스페이스·멀티터미널을 손으로.
- 목적: 컨테이너 이미지가 **대신 해주던 일**을 한 단계씩 체감.
- 모든 명령은 **한 줄씩 직접** 복사·실행하고 결과를 관찰한다.

## 주의
- 소스·venv·빌드 산출물 전부 `~/cobot_demo_ws/` 안에만 있음 → `rm -rf ~/cobot_demo_ws` 로 통째 정리(Part C).
- 두 실습 패키지는 설치 단계(README 3-1)에서 이미 `~/cobot_demo_ws/src/` 로 분리됨. 여기서 소스를 in-place 수정하지만 정식 워크스페이스 `~/cobot_ws` 는 안 건드린다.
- 정식 설치 경로 아님 — 비교 학습용.

## Part 0 — 사전 점검

한 줄씩 실행해 전제를 확인한다(하나라도 실패하면 정식 설치 먼저).

```bash
# ROS2 jazzy 존재
command -v ros2                                  # 예상: /opt/ros/jazzy/bin/ros2 경로 출력 (없으면 ROS 미설치/미source)
# host colcon 빌드본에 DSR + od_msg (overlay 의존)
ls ~/cobot_ws/install/dsr_common2/lib/python3.12/site-packages/DSR_ROBOT2.py   # 예상: 경로 출력
ls ~/cobot_ws/install/od_msg                     # 예상: include lib share
# 두 실습 패키지가 데모 ws 에 분리돼 있음 (README 3-1)
ls ~/cobot_demo_ws/src/pick_and_place_text ~/cobot_demo_ws/src/pick_and_place_voice
# config.sh (RMW/도메인 소스) 존재
ls ~/ros2_jazzy_test/resources/config.sh
```

## Part A — 1회 환경 구성
### A1. 실습 워크스페이스 분리 확인

두 실습 패키지는 정식 워크스페이스가 아니라 `~/cobot_demo_ws/src/` 에 있어야 한다(README 3-1).
`~/cobot_ws` 에 남아 있으면 정식 colcon 빌드에 딸려 들어가 `robot_control` 등 동명 패키지와 충돌한다.

```bash
ls ~/cobot_demo_ws/src/                                    # 예상: pick_and_place_text  pick_and_place_voice
ls ~/cobot_ws/src/cobot2/ | grep pick_and_place && echo "FAIL: 정식 ws 에 남아 있음" || echo "OK: 분리됨"
```

`FAIL` 이면 README 3-1 의 `mv` 를 먼저 실행한다.

### A2. voice 번들 rename + 마이크 fix

#### A2-1. 패키지 디렉토리 rename

`pick_and_place_voice` 안에 `robot_control`, `object_detection`, `voice_processing` 세 디렉토리가 있다.
워크스페이스는 갈라 놨지만 실행할 때 `~/cobot_ws/install` overlay 를 함께 source 하므로,
그쪽 동명 패키지와 python import 네임스페이스가 겹친다. `ppv_` 접두로 구조적으로 피한다.

```bash
cd ~/cobot_demo_ws/src/pick_and_place_voice
mv robot_control    ppv_robot_control
mv object_detection ppv_object_detection
mv voice_processing ppv_voice_processing
```

#### A2-2. import 교정 (line-anchored, 6줄)

> `^from ...` 앵커를 써서 노드명 문자열(`"robot_control_node"`, `'object_detection_node'`)은 건드리지 않는다.

```bash
cd ~/cobot_demo_ws/src/pick_and_place_voice
sed -i 's/^from robot_control\.onrobot import RG/from ppv_robot_control.onrobot import RG/' ppv_robot_control/robot_control.py
sed -i 's/^from object_detection\.realsense import ImgNode/from ppv_object_detection.realsense import ImgNode/' ppv_object_detection/detection.py
sed -i 's/^from object_detection\.yolo import YoloModel/from ppv_object_detection.yolo import YoloModel/' ppv_object_detection/detection.py
sed -i 's/^from voice_processing\.MicController import/from ppv_voice_processing.MicController import/' ppv_voice_processing/get_keyword.py
sed -i 's/^from voice_processing\.wakeup_word import WakeupWord/from ppv_voice_processing.wakeup_word import WakeupWord/' ppv_voice_processing/get_keyword.py
sed -i 's/^from voice_processing\.stt import STT/from ppv_voice_processing.stt import STT/' ppv_voice_processing/get_keyword.py
```

#### A2-2b. langchain 1.x 호환 (`langchain.prompts` 제거 대응)

`langchain` 1.0 부터 `langchain.prompts` 서브모듈이 제거되고 `PromptTemplate` 은 `langchain_core.prompts` 로 이동했다.
이 fix 없이는 get_keyword 가 import 단계에서 `ModuleNotFoundError: No module named 'langchain.prompts'` 로 즉시 죽는다 (컨테이너 working 버전도 동일 fix 적용).

```bash
cd ~/cobot_demo_ws/src/pick_and_place_voice
sed -i 's|^from langchain\.prompts import PromptTemplate|from langchain_core.prompts import PromptTemplate|' ppv_voice_processing/get_keyword.py
grep -n "^from langchain" ppv_voice_processing/get_keyword.py   # 예상: from langchain_core.prompts import PromptTemplate
```

#### A2-3. setup.py 교정

`find_packages` 목록과 `entry_points` 모듈 경로를 `ppv_*` 로 갱신한다.

```bash
cd ~/cobot_demo_ws/src/pick_and_place_voice
sed -i "s/'robot_control', /'ppv_robot_control', /;s/'voice_processing', /'ppv_voice_processing', /;s/'object_detection'/'ppv_object_detection'/" setup.py
sed -i "s#robot_control\.robot_control:main#ppv_robot_control.robot_control:main#;s#object_detection\.detection:main#ppv_object_detection.detection:main#;s#voice_processing\.get_keyword:main#ppv_voice_processing.get_keyword:main#" setup.py
```

#### A2-4. 검증

```bash
cd ~/cobot_demo_ws/src/pick_and_place_voice
# dangling import 0
grep -rnE "^from (robot_control|object_detection|voice_processing)\." . && echo "FAIL" || echo "imports OK"
# 노드명 문자열 보존
grep -q '"robot_control_node"' ppv_robot_control/robot_control.py && \
  grep -q "'object_detection_node'" ppv_object_detection/detection.py && echo "node-name strings OK"
# 파싱 무결성
python3 -c "import ast,glob; [ast.parse(open(f).read()) for f in glob.glob('ppv_*/**/*.py',recursive=True)+['setup.py']]; print('ast OK')"
# entry_points 확인
grep -E "ppv_(robot_control|object_detection|voice_processing)\.(robot_control|detection|get_keyword):main" setup.py
```

기대 출력: `imports OK` / `node-name strings OK` / `ast OK` / entry_point 3줄.

### A2-5. 마이크 입력 장치 고정 (16kHz 네이티브 DMIC)

> A2-5-2 (pyaudio probe) 와 A2-5-5 (device sanity) 는 venv 가 필요하므로 A3/A4 완료 후 실행한다 — 정적 수정(A2-5-1/3/4) 먼저 진행 후 런타임 확인.

**배경**: 이 워크스테이션 SOF DMIC 는 두 가지 캡처 장치로 노출된다.
- `hw:1,6` (48kHz 계열): 정적에서도 클리핑 노이즈 → wakeword confidence ≈ 0.001
- `hw:1,7` (16kHz 네이티브): 깨끗한 DMIC → confidence 0.7+

기본값(pyaudio 기본 장치)은 `hw:1,6` 쪽으로 가거나 resample 왜곡 → wakeword 탐지 실패.
아래 단계로 pyaudio(wakeword) 와 sounddevice(STT) 모두 `hw:1,7` 로 고정한다.

#### A2-5-1. audio_device.py 복사 (컨테이너 donor → monolithic)

```bash
cp ~/cobot_ws/src/cobot2/voice_container/voice_processing/voice_processing/audio_device.py \
   ~/cobot_demo_ws/src/pick_and_place_voice/ppv_voice_processing/audio_device.py
```

`audio_device.py` 의 `resolve_input_device()`: `VOICE_MIC_DEVICE` 환경변수 → 16kHz 네이티브 자동탐색 → None(ALSA 기본값 fallback). sounddevice 인덱스 기준.

#### A2-5-2. pyaudio 장치 인덱스 probe

> **각 머신마다 인덱스가 다를 수 있다.** 아래 명령으로 hw:1,7(16kHz, 입력채널>0) 에 해당하는 인덱스를 확인한다.

```bash
# venv 활성화 후 실행 (A3/A4 완료 상태)
~/cobot_demo_ws/.venv/bin/python -c "
import pyaudio
p = pyaudio.PyAudio()
[print(i, p.get_device_info_by_index(i)['name'],
       int(p.get_device_info_by_index(i)['defaultSampleRate']),
       p.get_device_info_by_index(i)['maxInputChannels'])
 for i in range(p.get_device_count())]
"
```

hw:1,7 / 16000Hz / 입력채널>0 에 해당하는 인덱스 N 을 기록한다.
**이 실습 머신 = 인덱스 9** (`sof-hda-dsp: - (hw:1,7)`, 16000Hz, 2ch).

#### A2-5-3. MicController.py 교정

rate 48kHz → 16kHz, `input_device_index` 주석 해제, device_index 실측 값으로 치환.

```bash
cd ~/cobot_demo_ws/src/pick_and_place_voice/ppv_voice_processing
sed -i 's/^    rate: int = 48000/    rate: int = 16000/' MicController.py
sed -i 's/^            # input_device_index=self.config.device_index/            input_device_index=self.config.device_index,/' MicController.py
N=9   # A2-5-2 probe 에서 확인한 인덱스로 교체 (이 머신 = 9)
sed -i "s/^    device_index: int = 10/    device_index: int = $N/" MicController.py
grep -n "rate: int\|device_index: int\|input_device_index" MicController.py
```

기대 출력: `rate: int = 16000` / `device_index: int = 9` / `input_device_index=self.config.device_index,`.

#### A2-5-4. stt.py 교정 (STT 녹음도 깨끗한 장치로)

```bash
cd ~/cobot_demo_ws/src/pick_and_place_voice/ppv_voice_processing
sed -i '/^import scipy.io.wavfile as wav/a from ppv_voice_processing.audio_device import resolve_input_device' stt.py
sed -i 's/sd\.rec(int(self\.duration \* self\.samplerate), samplerate=self\.samplerate, channels=1, dtype=.int16.)/sd.rec(int(self.duration * self.samplerate), samplerate=self.samplerate, channels=1, dtype="int16", device=resolve_input_device())/' stt.py
grep -n "audio_device\|resolve_input_device\|sd\.rec" stt.py
```

기대 출력: `from ppv_voice_processing.audio_device import resolve_input_device` + `sd.rec(... device=resolve_input_device())`.

#### A2-5-5. 검증

```bash
cd ~/cobot_demo_ws/src/pick_and_place_voice/ppv_voice_processing
python3 -c "import ast; [ast.parse(open(f).read()) for f in ['audio_device.py','MicController.py','stt.py']]; print('ast OK')"
grep -q "from ppv_voice_processing.audio_device import resolve_input_device" stt.py && echo "stt import OK"
grep -q "input_device_index=self.config.device_index," MicController.py && echo "mic device OK"
```

기대 출력: `ast OK` / `stt import OK` / `mic device OK`.

Device sanity (venv python 필요, A3/A4 완료 후):

```bash
~/cobot_demo_ws/.venv/bin/python -c "
import os, sys
sys.path.insert(0, os.path.expanduser('~/cobot_demo_ws/src/pick_and_place_voice'))
from ppv_voice_processing.audio_device import resolve_input_device
import pyaudio
idx = resolve_input_device()
print('resolve_input_device() =', idx)
p = pyaudio.PyAudio()
info = p.get_device_info_by_index(idx)
print('device:', info['name'], '| rate:', int(info['defaultSampleRate']))
stream = p.open(format=pyaudio.paInt16, channels=1, rate=16000, input=True,
                frames_per_buffer=1024, input_device_index=idx)
data = stream.read(1024, exception_on_overflow=False)
print('read bytes:', len(data))
stream.stop_stream(); stream.close(); p.terminate()
print('pyaudio open/read/close OK')
"
```

> **Live wakeword 검증** ("Hello Rokey" 발화 → confidence > 0.3)은 Task 7 voice 실행 절차에서 수행한다.

### A3. venv 생성

시스템 apt 패키지(pyaudio 컴파일, 오디오 파일 처리)를 먼저 확보한 뒤 venv 를 만든다.

```bash
# pyaudio 컴파일용 헤더 + libsndfile (컨테이너 미러)
# python3.12-venv 없으면 다음 줄 python3 -m venv 가 ensurepip 에러로 실패한다.
sudo apt install -y portaudio19-dev libsndfile1 python3.12-venv

# system-site-packages: rclpy / cv_bridge 등 ROS Python 바인딩 공유
# 워크스페이스 안에 두지만 이름이 `.` 로 시작 → colcon 이 스캔에서 건너뛴다(빌드 대상 아님).
python3 -m venv --system-site-packages ~/cobot_demo_ws/.venv
source ~/cobot_demo_ws/.venv/bin/activate
pip install --upgrade pip
```

확인:

```bash
python3 -c "import sys; print(sys.prefix)"  # 예상: /home/<user>/cobot_demo_ws/.venv
pip --version                                # 예상: pip 26.x from .../.venv/...
```

### A4. 의존성 설치 (pip)

> **처음이면 아래를 한 줄씩** 복사·실행하며 각 핀의 이유를 관찰한다(한 단계씩 체감하는 게 이 실습의 목적).
> 이미 한 번 마쳤고 venv 만 다시 만드는 거면 → 아래 **A4-fast** 로 `-r` 일괄 설치.

순서가 고정돼 있다. **numpy<2 재핀은 반드시 마지막**에 온다.

```bash
# (2) torch 최우선 — cu128 인덱스, 수 GB
pip install --index-url https://download.pytorch.org/whl/cu128 torch==2.11.0 torchvision==0.26.0

# YOLO + OpenCV 핀
pip install "ultralytics<9"
pip install "opencv-python<4.10"

# roboflow (YOLO 데이터셋 다운로드, OD_Tutorial/data_download.ipynb)
# 기본 설치는 opencv-python-headless 를 끌어와 위 opencv-python 과 cv2/ 가 충돌 → 본체만 --no-deps.
# typer/filetype/pi-heif/pillow-avif-plugin 은 opencv 를 안 끌어오므로 의존성 포함 일반 설치(typer 는 roboflow 전용 의존).
pip install typer filetype pi-heif pillow-avif-plugin
pip install --no-deps roboflow

# (3) LLM / 음성 스택
pip install "langchain<2" "langchain-openai<2" "openai<3" pyaudio sounddevice "scipy<1.18" python-dotenv

# (4) 그리퍼 Modbus — 3.7 부터 ModbusTcpClient 가 serial kwargs(stopbits 등)를 거부해 onrobot.py 가 TypeError 로 죽음 → <3.7 고정
pip install "pymodbus<3.7"

# (5) openwakeword — Python 3.12 에서 tflite-runtime 미지원 → no-deps 로 설치 후 의존성 직접 지정
# 아래 두 번째 줄이 끝나며 pip 이 붉은 ERROR 를 뱉는다 — 정상이다. 실패 아님(exit 0).
#   ERROR: pip's dependency resolver ... openwakeword 0.6.0 requires tflite-runtime<3,>=2.8.0 ... not installed
# --no-deps 로 건너뛴 그 의존을 pip 이 뒤늦게 일러 주는 것. 바로 아래 shim 이 그 자리를 메운다.
pip install --no-deps "openwakeword==0.6.0"
pip install "onnxruntime<2,>=1.10.0" "tqdm<5,>=4.0" "scikit-learn<2,>=1" "requests<3,>=2.0" "ai-edge-litert>=2.0.2,<3"

# tflite_runtime 호환 shim: ai_edge_litert 를 tflite_runtime.interpreter 이름으로 노출
python3 -c "
import os, ai_edge_litert as a
d = os.path.join(os.path.dirname(os.path.dirname(a.__file__)), 'tflite_runtime')
os.makedirs(d, exist_ok=True)
open(os.path.join(d, '__init__.py'), 'w').close()
open(os.path.join(d, 'interpreter.py'), 'w').write('from ai_edge_litert.interpreter import Interpreter  # noqa: F401\n')
"

# openwakeword feature 모델 복사 (레포 동봉본 resources/oww_models/ → 설치 경로)
OWW_DIR="$(python3 -c 'import os,openwakeword;print(os.path.join(os.path.dirname(openwakeword.__file__),"resources","models"))')"
mkdir -p "$OWW_DIR" && cp ~/ros2_jazzy_test/resources/oww_models/* "$OWW_DIR"/

# TFL3 매직바이트 검증
python3 -c "
import os
d = '$OWW_DIR'
[(open(os.path.join(d,f),'rb').read(8)[4:8]==b'TFL3') or (_ for _ in ()).throw(SystemExit('corrupt tflite: '+f)) for f in os.listdir(d) if f.endswith('.tflite')]
print('feature models TFL3 OK')
"

# (6) numpy<2 마지막 재핀 — ultralytics 가 numpy>=2 를 끌어오므로 반드시 최후에
pip install --force-reinstall "numpy<2"
```

검증:

```bash
python3 -c "
import numpy,torch,ultralytics,cv2,langchain,langchain_openai,openai
import pyaudio,sounddevice,scipy,openwakeword,ai_edge_litert
import tflite_runtime.interpreter,pymodbus,roboflow
assert numpy.__version__.startswith('1.'), numpy.__version__
print('deps OK', numpy.__version__)
"
```

기대 출력: `deps OK 1.26.x`

여기까지는 **import 만** 확인한 것이다. `import openwakeword` 는 `.tflite` 를 열지 않으므로,
위 모델 복사가 통째로 실패해도 이 블록은 그대로 `deps OK` 를 찍는다. 앞의 TFL3 검사도 마찬가지 —
검사 대상 파일이 0개면 아무것도 안 보고 통과한다. 그 상태로 넘어가면 실습 당일
`ros2 run` 에서 `ValueError: Could not open ... melspectrogram.tflite` 로 깨진다.

그래서 wakeword 모델을 실제로 올려 추론 1회까지 돌려 본다. 이게 진짜 게이트다.

```bash
python3 -c "
import numpy as np
from openwakeword.model import Model
m = Model(wakeword_models=['$HOME/cobot_demo_ws/src/pick_and_place_voice/resource/hello_rokey_8332_32.tflite'])
m.predict(np.zeros(1280, dtype=np.int16))
print('wakeword gate OK — Model(.tflite) load + predict')
"
```

기대 출력: `wakeword gate OK — Model(.tflite) load + predict`
(`INFO: Created TensorFlow Lite XNNPACK delegate for CPU.` 가 함께 나오면 정상)

`Model(...)` 은 shim 을 거쳐 `melspectrogram.tflite` / `embedding_model.tflite` 를 로드한다.
즉 이 한 줄이 **의존성 · shim · feature 모델 · wakeword 모델**을 한꺼번에 확증한다.

### A4-fast. 빠른 경로 (선택 · venv 재구성용)

> 이미 A4 를 한 번 해 본 사람이 venv 를 다시 만들 때만. 처음이면 위 A4 를 한 줄씩(학습).
> 완전 원샷은 불가 — `--no-deps`(openwakeword/roboflow)·별도 index(torch)·numpy 최후 재핀은 `-r` 로 못 묶는다.
> 그래서 **`-r` 일괄 1콜 + 특수 3콜 + shim/모델 블록**으로 정리한다. 각 단계 의미는 위 A4 참조.

```bash
# venv 활성화 상태에서(A3 완료). 실행 순서 고정 — numpy<2 재핀은 반드시 최후.

# 1) torch — 별도 cu128 인덱스라 -r 로 못 묶음(수 GB)
pip install --index-url https://download.pytorch.org/whl/cu128 torch==2.11.0 torchvision==0.26.0

# 2) 나머지 정상-의존 패키지 일괄 — requirements.txt 활성 줄(A4 의 ultralytics/opencv/langchain/pymodbus/
#    onnxruntime·typer 그룹을 한 방에). openwakeword/roboflow/numpy 는 파일에서 주석이라 여기서 안 깔림.
pip install -r ~/ros2_jazzy_test/scripts/venv-demo/requirements.txt

# 3) --no-deps 스트래글러 — openwakeword(tflite-runtime 3.12 wheel 없음) · roboflow(opencv-headless 충돌) 회피
pip install --no-deps "openwakeword==0.6.0" "roboflow<2"

# 4) tflite shim + feature 모델 복사 + TFL3 검증:
#    위 A4 코드블록의 주석 "# tflite_runtime 호환 shim" / "# openwakeword feature 모델 복사" /
#    "# TFL3 매직바이트 검증" 3개 파트를 그대로 실행(내용 동일 — 여기 중복 표기 안 함).

# 5) numpy<2 최후 재핀 — ultralytics·torch 가 numpy>=2 를 끌어오므로 반드시 마지막
pip install --force-reinstall "numpy<2"
```

검증은 A4 의 import 블록 + **wakeword 게이트** 두 개 모두 실행 → `deps OK 1.26.x`, `wakeword gate OK`.
import 블록만으로는 모델 복사 실패를 못 잡는다(A4 의 설명 참조).

### A4b. voice 에셋 스테이징

`pick_and_place_voice` 노드는 `.pt` 모델과 카메라 캘리브레이션 행렬 `.npy` 를 자체 `resource/` 에서 읽는다. `pick_and_place_text` 에 있는 파일을 복사해 준다.

```bash
cp ~/cobot_demo_ws/src/pick_and_place_text/resource/yolov8n_tools_0122.pt \
   ~/cobot_demo_ws/src/pick_and_place_voice/resource/

cp ~/cobot_demo_ws/src/pick_and_place_text/resource/T_gripper2camera.npy \
   ~/cobot_demo_ws/src/pick_and_place_voice/resource/
```

확인:

```bash
ls ~/cobot_demo_ws/src/pick_and_place_voice/resource/yolov8n_tools_0122.pt \
   ~/cobot_demo_ws/src/pick_and_place_voice/resource/T_gripper2camera.npy
# 두 경로가 출력되면 OK
```

### A5. colcon 빌드 (데모 워크스페이스)

소스가 이미 별도 워크스페이스에 있으니 그 자리에서 빌드한다 — `~/cobot_ws/install` 은 손대지 않는다.  
`~/cobot_ws/install` 이 underlay — DSR + od_msg 는 여기서 온다.

```bash
deactivate 2>/dev/null || true
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
cd ~/cobot_demo_ws && colcon build
```

기대 출력: `Summary: 2 packages finished` (경고는 무시 가능).

검증 (새 터미널 또는 동일 세션에서):

```bash
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
source ~/cobot_demo_ws/install/setup.bash
ros2 pkg list | grep -E "pick_and_place_(text|voice)"
ls ~/cobot_demo_ws/install/pick_and_place_voice/share/pick_and_place_voice/resource/yolov8n_tools_0122.pt
python3 -c "from ament_index_python.packages import get_package_share_directory as g; print(g('pick_and_place_text')); print(g('pick_and_place_voice'))"
```

기대 출력:
- `pick_and_place_text` / `pick_and_place_voice` 두 줄
- `.pt` 경로 출력
- overlay 내 두 share 경로 출력 (에러 없음)

## Part B — 실행
### text 데모 (터미널 3개)

> **전제**: Part A 전 단계 완료 (`~/cobot_demo_ws/` 에 venv + colcon 빌드 완료).

#### 터미널 1 — 드라이버 + 카메라 (bringup, 가상 에뮬레이터)

```bash
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
ros2 launch cobot2_bringup bringup_all.launch.py mode:=virtual
# 실로봇: ros2 launch cobot2_bringup bringup_all.launch.py mode:=real host:=192.168.1.100
```

기대 출력: DSR 에뮬레이터 + RealSense 드라이버 노드 기동 (터미널 1 은 이 상태로 유지).

#### 터미널 2 — YOLO depth 서비스 노드 (detection, venv)

```bash
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
source ~/cobot_demo_ws/install/setup.bash
export PYTHONPATH="$(ls -d ~/cobot_demo_ws/.venv/lib/python*/site-packages):$PYTHONPATH"
ros2 run pick_and_place_text detection
```

기대 출력: YOLO 모델 로드 로그 → `Waiting for client's call...` (카메라 토픽 대기).  
에뮬레이터 없이 실행 시 카메라 topic 수신 대기 상태로 머무는 것은 정상 — `ModuleNotFoundError` / `FileNotFoundError` 없으면 OK.

#### 터미널 3 — 오케스트레이터 (robot_move, venv)

```bash
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
source ~/cobot_demo_ws/install/setup.bash
export PYTHONPATH="$(ls -d ~/cobot_demo_ws/.venv/lib/python*/site-packages):$PYTHONPATH"
ros2 run pick_and_place_text robot_move
```

기대 출력: DSR 노드 초기화 (`_robot_id=dsr01`, `_robot_model=m0609`) → MoveJ 서비스 대기 로그.  
OnRobot 그리퍼는 노드 import 시 생성되어 `192.168.1.1:502` Modbus TCP 연결을 시도한다 — 그리퍼 하드웨어 없이는 노드가 초기화되지만 해당 연결/그리퍼 동작 지점에서 멈추는 것이 예상 동작 [HW].  
에뮬레이터 없이 실행 시 `MoveJ Service is not available, waiting...` 가 반복되는 것은 정상 [HW/emulator].

> **전체 파이프라인** (bringup virtual + RealSense 카메라 + 실제 pick&place 모션) 검증은 에뮬레이터 + 그리퍼 하드웨어가 필요한 별도 단계 — [HW/emulator] 에서 수행.

### voice 데모 (터미널 4개)

> **전제**: Part A 전 단계 완료 (`~/cobot_demo_ws/` 에 venv + colcon 빌드 완료).

#### 터미널 1 — 드라이버 + 카메라 (bringup, text 와 동일)

```bash
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
ros2 launch cobot2_bringup bringup_all.launch.py mode:=virtual
# 실로봇: ros2 launch cobot2_bringup bringup_all.launch.py mode:=real host:=192.168.1.100
```

기대 출력: DSR 에뮬레이터 + RealSense 드라이버 노드 기동 (터미널 1 은 이 상태로 유지).

#### 터미널 2 — YOLO depth 서비스 노드 (object_detection, venv)

```bash
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
source ~/cobot_demo_ws/install/setup.bash
export PYTHONPATH="$(ls -d ~/cobot_demo_ws/.venv/lib/python*/site-packages):$PYTHONPATH"
ros2 run pick_and_place_voice object_detection
```

기대 출력: YOLO 모델 로드 → `[img_node]: Waiting for client's call...` (카메라 토픽 대기).  
에뮬레이터 없이 실행 시 카메라 topic 수신 대기 상태로 머무는 것은 정상 — `ModuleNotFoundError` / `FileNotFoundError` 없으면 OK.

#### 터미널 3 — 음성 명령 처리 (get_keyword, venv) — OpenAI 키 여기에만

```bash
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
source ~/cobot_demo_ws/install/setup.bash
export PYTHONPATH="$(ls -d ~/cobot_demo_ws/.venv/lib/python*/site-packages):$PYTHONPATH"
export OPENAI_API_KEY=sk-...   # ← 실제 key 입력 (이 터미널에서만 — robot_control 은 불요)
ros2 run pick_and_place_voice get_keyword
```

> **OpenAI 소비처는 이 노드(get_keyword)** 뿐이다. `ChatOpenAI` (LLM 명령 파싱) + `STT` (Whisper) 가 여기서 호출된다. `robot_control` 은 `/get_keyword` ROS2 서비스를 호출할 뿐 — key 불요.

> **`.env` 대안**: `load_dotenv` 는 설치된 `share/pick_and_place_voice/resource/.env` 를 읽는다.  
> 소스에 `.env` 를 두면 `colcon build` 재실행 후에야 install 경로에 반영 → 셸 `export` 권장.

기대 출력: `MicRecorderNode initialized.` → `wait for client's request...` (wakeword "Hello Rokey" 대기 상태).

#### 터미널 4 — 로봇 동작 (robot_control, venv)

```bash
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
source ~/cobot_demo_ws/install/setup.bash
export PYTHONPATH="$(ls -d ~/cobot_demo_ws/.venv/lib/python*/site-packages):$PYTHONPATH"
ros2 run pick_and_place_voice robot_control
```

기대 출력: DSR 노드 초기화 (`_robot_id=dsr01`) → `MoveJ Service is not available, waiting...` (에뮬레이터 없을 때 정상 [HW/emulator]).  
OnRobot 그리퍼는 노드 import 시 생성되어 `192.168.1.1:502` Modbus TCP 연결을 시도한다 — 그리퍼 하드웨어 없이는 노드가 초기화되지만 해당 연결/그리퍼 동작 지점에서 멈추는 것이 예상 동작 [HW].

#### 전체 파이프라인 검증 [HW]

"Hello Rokey" 발화 → get_keyword 가 confidence > 0.3 탐지 → STT 5 초 → LLM 파싱 → robot_control 이 pick & place 모션 실행.  
마이크 연결 + 실제 `OPENAI_API_KEY` + 에뮬레이터(또는 실로봇) 환경 필요 — 별도 [HW] 단계에서 수행.

## Part C — 정리 & 대비
- 방금 친 명령 수를 세어 본다. **컨테이너 방식이었다면**:
  ```bash
  bash ~/ros2_jazzy_test/containers/bringup.sh mode:=virtual   # 드라이버+카메라
  docker compose -f ~/ros2_jazzy_test/containers/docker-compose.yml up -d   # yolo+voice
  ```
  두 줄. 이미지가 의존성·핀·shim·네임스페이스·빌드를 전부 선처리.
- 정리(원복) — 소스·venv·빌드가 한 디렉토리 안에 있어 한 줄이다:
  ```bash
  rm -rf ~/cobot_demo_ws
  ```
  rename · import 6줄 · langchain 패치 · MicController/stt 수정이 전부 이 안에 있었으므로 함께 사라진다.
  정식 워크스페이스 `~/cobot_ws` 는 처음부터 변경된 적이 없다.

  다시 실습하려면 README 3-1 을 재실행한다(원본 사본 `~/Downloads/cobot2` 필요).

| 관점 | 컨테이너 | venv(이 문서) |
|------|---------|--------------|
| 의존성 설치 | 이미지에 선반영 | 수동 pip(torch 수 GB, numpy<2 순서, openwakeword shim) |
| 네임스페이스 충돌 | FS 격리로 무관 | `robot_control` 등 rename 필요 |
| 마이크/장치 | 이미지+asound.conf | 장치 인덱스 수동 probe |
| 기동 | 2줄 | 7개 터미널·다수 명령 |
| 정리 | `compose down` | `rm -rf ~/cobot_demo_ws` + 소스 재배치 |
