# pick & place 실습 — venv

### 1. 사전 점검

```bash
# 1) ROS2 jazzy + config.sh
command -v ros2                                  # → /opt/ros/jazzy/bin/ros2
ls ~/ros2_jazzy_test/resources/config.sh

# 2) od_msg, cobot2 소스 배치 확인
ls -d ~/cobot_ws/src/cobot2/yolo_container/od_msg

# 3) 정식 ws 빌드본
ls ~/cobot_ws/install/dsr_common2/lib/python3.12/site-packages/DSR_ROBOT2.py

# 4) 실습 패키지 배치 확인
ls ~/cobot_demo_ws/src/                          # → pick_and_place_text  pick_and_place_voice
```

### 2. 인터페이스 패키지 준비 (DSR + od_msg)

```bash
# 1) doosan-robot2 두 패키지만 복사
git clone --depth 1 https://github.com/ROKEY-SPARK/doosan-robot2_jazzy.git ~/cobot_demo_ws/doosan-robot2
cp -r ~/cobot_demo_ws/doosan-robot2/dsr_common2 ~/cobot_demo_ws/doosan-robot2/dsr_msgs2 ~/cobot_demo_ws/src/
rm -rf ~/cobot_demo_ws/doosan-robot2

# 2) od_msg — cobot2 소스에서 복사
cp -r ~/cobot_ws/src/cobot2/yolo_container/od_msg ~/cobot_demo_ws/src/

# 검증
ls ~/cobot_demo_ws/src/   # → dsr_common2  dsr_msgs2  od_msg  pick_and_place_text  pick_and_place_voice
```

### 3. venv 생성

```bash
# 1) 시스템 라이브러리
sudo apt install -y portaudio19-dev libsndfile1 python3.12-venv

# 2) venv
python3 -m venv --system-site-packages ~/cobot_demo_ws/.venv
source ~/cobot_demo_ws/.venv/bin/activate
pip install --upgrade pip

# 검증
python3 -c "import sys; print(sys.prefix)"       # → /home/<user>/cobot_demo_ws/.venv
```

### 4. 의존성 설치 (pip)

```bash
# 1) torch — cu128
pip install --index-url https://download.pytorch.org/whl/cu128 torch==2.11.0 torchvision==0.26.0

# 2) YOLO + OpenCV
pip install "ultralytics<9"
pip install "opencv-python<4.10"

# 3) roboflow
pip install typer filetype pi-heif pillow-avif-plugin
pip install --no-deps roboflow

# 4) LLM / 음성 스택
pip install "langchain<2" "langchain-openai<2" "openai<3" pyaudio sounddevice "scipy<1.18" python-dotenv

# 5) 그리퍼 Modbus
pip install "pymodbus<3.7"

# 6) openwakeword
pip install --no-deps "openwakeword==0.6.0"
pip install "onnxruntime<2,>=1.10.0" "tqdm<5,>=4.0" "scikit-learn<2,>=1" "requests<3,>=2.0" "ai-edge-litert>=2.0.2,<3"

# 7) tflite_runtime
python3 -c "
import os, ai_edge_litert as a
d = os.path.join(os.path.dirname(os.path.dirname(a.__file__)), 'tflite_runtime')
os.makedirs(d, exist_ok=True)
open(os.path.join(d, '__init__.py'), 'w').close()
open(os.path.join(d, 'interpreter.py'), 'w').write('from ai_edge_litert.interpreter import Interpreter  # noqa: F401\n')
"

# 8) openwakeword feature 모델 복사
OWW_DIR="$(python3 -c 'import os,openwakeword;print(os.path.join(os.path.dirname(openwakeword.__file__),"resources","models"))')"
mkdir -p "$OWW_DIR" && cp ~/ros2_jazzy_test/resources/oww_models/* "$OWW_DIR"/
python3 -c "
import os
d = '$OWW_DIR'
[(open(os.path.join(d,f),'rb').read(8)[4:8]==b'TFL3') or (_ for _ in ()).throw(SystemExit('corrupt tflite: '+f)) for f in os.listdir(d) if f.endswith('.tflite')]
print('feature models TFL3 OK')
"

# 9) numpy<2 재핀
pip install --force-reinstall "numpy<2"

# 검증 1 — import
python3 -c "
import numpy,torch,ultralytics,cv2,langchain,langchain_openai,openai
import pyaudio,sounddevice,scipy,openwakeword,ai_edge_litert
import tflite_runtime.interpreter,pymodbus,roboflow
assert numpy.__version__.startswith('1.'), numpy.__version__
print('deps OK', numpy.__version__)
"                                                # → deps OK 1.26.x

# 검증 2 — wakeword 게이트
python3 -c "
import numpy as np
from openwakeword.model import Model
m = Model(wakeword_models=['$HOME/cobot_demo_ws/src/pick_and_place_voice/resource/hello_rokey_8332_32.tflite'])
m.predict(np.zeros(1280, dtype=np.int16))
print('wakeword gate OK')
"                                                # → wakeword gate OK
```

### 5. 마이크 장치 확인

```bash
# 장치 확인
~/cobot_demo_ws/.venv/bin/python -c "
import os, sys
sys.path.insert(0, os.path.expanduser('~/cobot_demo_ws/src/pick_and_place_voice'))
from voice_processing.audio_device import resolve_input_device
import pyaudio
idx = resolve_input_device()
p = pyaudio.PyAudio()
info = p.get_device_info_by_index(idx)
print('device:', idx, info['name'], '| rate:', int(info['defaultSampleRate']))
stream = p.open(format=pyaudio.paInt16, channels=1, rate=16000, input=True,
                frames_per_buffer=1024, input_device_index=idx)
data = stream.read(1024, exception_on_overflow=False)
stream.stop_stream(); stream.close(); p.terminate()
print('pyaudio open/read/close OK')
"
```

다른 기기 사용 시 확인

```bash
~/cobot_demo_ws/.venv/bin/python -c "
import pyaudio
p = pyaudio.PyAudio()
[print(i, p.get_device_info_by_index(i)['name'],
       int(p.get_device_info_by_index(i)['defaultSampleRate']),
       p.get_device_info_by_index(i)['maxInputChannels'])
 for i in range(p.get_device_count())]
"
```

### 6. voice 에셋 + OPENAI 키

```bash
# 1) yolo 모델 + 캘리브레이션 (pick_and_place_text 에서 복사)
cp ~/cobot_demo_ws/src/pick_and_place_text/resource/yolov8n_tools_0122.pt \
   ~/cobot_demo_ws/src/pick_and_place_voice/resource/
cp ~/cobot_demo_ws/src/pick_and_place_text/resource/T_gripper2camera.npy \
   ~/cobot_demo_ws/src/pick_and_place_voice/resource/

# 2) OPENAI 키 
echo 'OPENAI_API_KEY=<본인_OpenAI_API_키>' > ~/cobot_demo_ws/src/pick_and_place_voice/resource/.env

# 검증
ls ~/cobot_demo_ws/src/pick_and_place_voice/resource/yolov8n_tools_0122.pt \
   ~/cobot_demo_ws/src/pick_and_place_voice/resource/T_gripper2camera.npy \
   ~/cobot_demo_ws/src/pick_and_place_voice/resource/.env   # → 세 경로 출력
```

### 7. colcon 빌드

```bash
deactivate 2>/dev/null || true
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
cd ~/cobot_demo_ws && colcon build
# → Summary: 5 packages finished

# 검증
source /opt/ros/jazzy/setup.bash
source ~/cobot_demo_ws/install/setup.bash
ros2 pkg list | grep -E "pick_and_place_(text|voice)|dsr_common2|dsr_msgs2|od_msg"   # → 5줄
ls ~/cobot_demo_ws/install/pick_and_place_voice/share/pick_and_place_voice/resource/yolov8n_tools_0122.pt

python3 -c "import DR_init; from DSR_ROBOT2 import movej; from od_msg.srv import SrvDepthPosition; print('interface imports OK')"
```

### 8. 실행 — text 데모

```bash
# 터미널 1 — 드라이버 + 카메라 (bringup)
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
ros2 launch m0609_rg2_bringup bringup.launch.py mode:=virtual camera:=true
# 실로봇: ros2 launch m0609_rg2_bringup bringup.launch.py mode:=real host:=192.168.1.100
# camera:=true 를 붙이는 이유 — 이 launch 의 camera 기본값은 false 다(standalone 개발 시 USB 카메라
# 를 잡지 않기 위함). virtual 에서도 YOLO depth 서비스가 카메라 토픽을 필요로 하므로 명시한다.
```

```bash
# 터미널 2 — YOLO depth 서비스 노드 (detection, venv)
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_demo_ws/install/setup.bash
export PYTHONPATH="$(ls -d ~/cobot_demo_ws/.venv/lib/python*/site-packages):$PYTHONPATH"
ros2 run pick_and_place_text detection --ros-args -r img_node:__ns:=/camera
# remap 이 필요한 이유 — 이 노드 안의 img_node 는 카메라 토픽을 절대 경로가 아니라 상대 이름
# ('color/image_raw' 등)으로 구독한다. 상대 이름은 노드 네임스페이스가 붙어 최종 이름이 되므로
# img_node 를 /camera 네임스페이스로 옮겨야 bringup 이 내는 /camera/color/image_raw 와 맞는다.
# 'img_node:' 접두사를 빼고 -r __ns:=/camera 로 쓰면 같은 프로세스의 detection 노드까지 옮겨져
# robot_move 가 부르는 /get_3d_position 서비스 경로가 끊긴다.
# → YOLO 로드 → "Waiting for client's call..." (에뮬레이터 없으면 카메라 토픽 대기 = 정상)
# remap 을 빠뜨려도 노드는 에러 없이 그냥 뜬다 — 토픽만 조용히 비어 있다.
```

```bash
# 터미널 3 — 오케스트레이터 (robot_move, venv)
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_demo_ws/install/setup.bash
export PYTHONPATH="$(ls -d ~/cobot_demo_ws/.venv/lib/python*/site-packages):$PYTHONPATH"
ros2 run pick_and_place_text robot_move
# → DSR 노드 초기화(_robot_id=dsr01) → MoveJ 서비스 대기. 에뮬레이터 없이 "waiting..." 반복 = 정상 [HW/emulator]
# → OnRobot 그리퍼는 import 시 192.168.1.1:502 Modbus 연결 시도 — 하드웨어 없으면 그 지점에서 멈춤 = 정상 [HW]
```

### 9. 실행 — voice 데모

```bash
# 터미널 1 — 드라이버 + 카메라
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
ros2 launch m0609_rg2_bringup bringup.launch.py mode:=virtual camera:=true
```

```bash
# 터미널 2 — YOLO depth 서비스 노드 (object_detection, venv)
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_demo_ws/install/setup.bash
export PYTHONPATH="$(ls -d ~/cobot_demo_ws/.venv/lib/python*/site-packages):$PYTHONPATH"
ros2 run pick_and_place_voice object_detection --ros-args -r img_node:__ns:=/camera
# remap 이 필요한 이유는 §8 터미널 2 와 동일 — img_node 만 /camera 네임스페이스로 옮겨
# 상대 이름 'color/image_raw' 를 /camera/color/image_raw 로 해석시킨다.
# robot_control 이 부르는 /get_3d_position 은 접두사 'img_node:' 덕에 루트에 그대로 남는다.
# → YOLO 로드 → "[img_node]: Waiting for client's call..." (카메라 토픽 대기 = 정상)
```

```bash
# 터미널 3 — 음성 명령 처리 (get_keyword, venv)
# OpenAI 소비처는 이 노드뿐(ChatOpenAI + Whisper STT) — 키는 §6 의 .env 가 빌드에 내장돼 있어 export 불요
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_demo_ws/install/setup.bash
export PYTHONPATH="$(ls -d ~/cobot_demo_ws/.venv/lib/python*/site-packages):$PYTHONPATH"
ros2 run pick_and_place_voice get_keyword
# → "MicRecorderNode initialized." → "wait for client's request..." (wakeword "Hello Rokey" 대기)
```

```bash
# 터미널 4 — 로봇 동작 (robot_control, venv)
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_demo_ws/install/setup.bash
export PYTHONPATH="$(ls -d ~/cobot_demo_ws/.venv/lib/python*/site-packages):$PYTHONPATH"
ros2 run pick_and_place_voice robot_control
```

### 10. 정리 (teardown)

```bash
rm -rf ~/cobot_demo_ws
```
