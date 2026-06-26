# pick & place 실습 — 컨테이너 없이 venv 로 실행하기

## 이게 뭔가
- 같은 pick & place 기능을 **두 가지 방식**으로 본다:
  - **컨테이너 방식(정식)**: `bash ~/ros2_jazzy_test/containers/bringup.sh` + `docker compose up -d` — 몇 줄로 끝.
  - **venv 방식(이 문서)**: 모놀리식 노드를 host venv 로 직접 — 의존성 설치·핀·네임스페이스·멀티터미널을 손으로.
- 목적: 컨테이너 이미지가 **대신 해주던 일**을 한 단계씩 체감.
- 모든 명령은 **한 줄씩 직접** 복사·실행하고 결과를 관찰한다.

## 주의
- 데모 산출물은 `~/.cobot2_venv_demo/` 에만 생성 → `rm -rf ~/.cobot2_venv_demo` 로 정리(Part C).
- `~/cobot_ws/src/cobot2` 원본을 in-place 수정한다(비추적). 되돌리려면 Part C 참고.
- 정식 설치 경로 아님 — 비교 학습용.

## Part 0 — 사전 점검

한 줄씩 실행해 전제를 확인한다(하나라도 실패하면 정식 설치 먼저).

```bash
# ROS2 jazzy 존재
command -v ros2                                  # 예상: /opt/ros/jazzy/bin/ros2 경로 출력 (없으면 ROS 미설치/미source)
# host colcon 빌드본에 DSR + od_msg (overlay 의존)
ls ~/cobot_ws/install/dsr_common2/lib/python3.12/site-packages/DSR_ROBOT2.py   # 예상: 경로 출력
ls ~/cobot_ws/install/od_msg                     # 예상: include lib share
# 두 원본 패키지 존재
ls ~/cobot_ws/src/cobot2/pick_and_place_text ~/cobot_ws/src/cobot2/pick_and_place_voice
# config.sh (RMW/도메인 소스) 존재
ls ~/ros2_jazzy_test/resources/config.sh
```

## Part A — 1회 환경 구성
### A1. 원본 패키지 활성화 (COLCON_IGNORE 제거)

두 패키지는 기본 비활성(COLCON_IGNORE) 상태다. 파일을 지우면 colcon 이 인식한다.

```bash
rm ~/cobot_ws/src/cobot2/pick_and_place_text/COLCON_IGNORE
rm ~/cobot_ws/src/cobot2/pick_and_place_voice/COLCON_IGNORE
```

확인:

```bash
ls ~/cobot_ws/src/cobot2/pick_and_place_text/COLCON_IGNORE 2>&1 || echo "OK: 삭제됨"
ls ~/cobot_ws/src/cobot2/pick_and_place_voice/COLCON_IGNORE 2>&1 || echo "OK: 삭제됨"
```

### A2. voice 번들 rename + 마이크 fix

#### A2-1. 패키지 디렉토리 rename

`pick_and_place_voice` 안에 `robot_control`, `object_detection`, `voice_processing` 세 디렉토리가 있다.
host colcon 워크스페이스에 이미 동일 이름 패키지가 있어 충돌하므로 `ppv_` 접두를 붙인다.

```bash
cd ~/cobot_ws/src/cobot2/pick_and_place_voice
mv robot_control    ppv_robot_control
mv object_detection ppv_object_detection
mv voice_processing ppv_voice_processing
```

#### A2-2. import 교정 (line-anchored, 6줄)

> `^from ...` 앵커를 써서 노드명 문자열(`"robot_control_node"`, `'object_detection_node'`)은 건드리지 않는다.

```bash
cd ~/cobot_ws/src/cobot2/pick_and_place_voice
sed -i 's/^from robot_control\.onrobot import RG/from ppv_robot_control.onrobot import RG/' ppv_robot_control/robot_control.py
sed -i 's/^from object_detection\.realsense import ImgNode/from ppv_object_detection.realsense import ImgNode/' ppv_object_detection/detection.py
sed -i 's/^from object_detection\.yolo import YoloModel/from ppv_object_detection.yolo import YoloModel/' ppv_object_detection/detection.py
sed -i 's/^from voice_processing\.MicController import/from ppv_voice_processing.MicController import/' ppv_voice_processing/get_keyword.py
sed -i 's/^from voice_processing\.wakeup_word import WakeupWord/from ppv_voice_processing.wakeup_word import WakeupWord/' ppv_voice_processing/get_keyword.py
sed -i 's/^from voice_processing\.stt import STT/from ppv_voice_processing.stt import STT/' ppv_voice_processing/get_keyword.py
```

#### A2-3. setup.py 교정

`find_packages` 목록과 `entry_points` 모듈 경로를 `ppv_*` 로 갱신한다.

```bash
cd ~/cobot_ws/src/cobot2/pick_and_place_voice
sed -i "s/'robot_control', /'ppv_robot_control', /;s/'voice_processing', /'ppv_voice_processing', /;s/'object_detection'/'ppv_object_detection'/" setup.py
sed -i "s#robot_control\.robot_control:main#ppv_robot_control.robot_control:main#;s#object_detection\.detection:main#ppv_object_detection.detection:main#;s#voice_processing\.get_keyword:main#ppv_voice_processing.get_keyword:main#" setup.py
```

#### A2-4. 검증

```bash
cd ~/cobot_ws/src/cobot2/pick_and_place_voice
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
### A3. venv 생성

시스템 apt 패키지(pyaudio 컴파일, 오디오 파일 처리)를 먼저 확보한 뒤 venv 를 만든다.

```bash
# pyaudio 컴파일용 헤더 + libsndfile (컨테이너 미러)
# python3.12-venv 없으면 다음 줄 python3 -m venv 가 ensurepip 에러로 실패한다.
sudo apt install -y portaudio19-dev libsndfile1 python3.12-venv

# system-site-packages: rclpy / cv_bridge 등 ROS Python 바인딩 공유
python3 -m venv --system-site-packages ~/.cobot2_venv_demo/venv
source ~/.cobot2_venv_demo/venv/bin/activate
pip install --upgrade pip
```

확인:

```bash
python3 -c "import sys; print(sys.prefix)"  # 예상: /home/<user>/.cobot2_venv_demo/venv
pip --version                                # 예상: pip 26.x from .../venv/...
```

### A4. 의존성 설치 (pip)

순서가 고정돼 있다. **numpy<2 재핀은 반드시 마지막**에 온다.

```bash
# (2) torch 최우선 — cu128 인덱스, 수 GB
pip install --index-url https://download.pytorch.org/whl/cu128 torch torchvision

# YOLO + OpenCV 핀
pip install "ultralytics<9"
pip install "opencv-python<4.10"

# (3) LLM / 음성 스택
pip install "langchain<2" "langchain-openai<2" "openai<3" pyaudio sounddevice "scipy<1.18" python-dotenv

# (4) 그리퍼 Modbus
pip install pymodbus

# (5) openwakeword — Python 3.12 에서 tflite-runtime 미지원 → no-deps 로 설치 후 의존성 직접 지정
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

# openwakeword feature 모델 복사 (컨테이너 oww_models/ → 설치 경로)
OWW_DIR="$(python3 -c 'import os,openwakeword;print(os.path.join(os.path.dirname(openwakeword.__file__),"resources","models"))')"
mkdir -p "$OWW_DIR" && cp ~/ros2_jazzy_test/containers/voice-processing/oww_models/* "$OWW_DIR"/

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
import tflite_runtime.interpreter,pymodbus
assert numpy.__version__.startswith('1.'), numpy.__version__
print('deps OK', numpy.__version__)
"
```

기대 출력: `deps OK 1.26.x`

### A4b. voice 에셋 스테이징

`pick_and_place_voice` 노드는 `.pt` 모델과 카메라 캘리브레이션 행렬 `.npy` 를 자체 `resource/` 에서 읽는다. `pick_and_place_text` 에 있는 파일을 복사해 준다.

```bash
cp ~/cobot_ws/src/cobot2/pick_and_place_text/resource/yolov8n_tools_0122.pt \
   ~/cobot_ws/src/cobot2/pick_and_place_voice/resource/

cp ~/cobot_ws/src/cobot2/pick_and_place_text/resource/T_gripper2camera.npy \
   ~/cobot_ws/src/cobot2/pick_and_place_voice/resource/
```

확인:

```bash
ls ~/cobot_ws/src/cobot2/pick_and_place_voice/resource/yolov8n_tools_0122.pt \
   ~/cobot_ws/src/cobot2/pick_and_place_voice/resource/T_gripper2camera.npy
# 두 경로가 출력되면 OK
```

### A5. colcon 빌드 (격리 overlay)

## Part B — 실행
### text 데모 (터미널 3개)
### voice 데모 (터미널 4개)

## Part C — 정리 & 대비
