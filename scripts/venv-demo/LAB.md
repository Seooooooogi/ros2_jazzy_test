# pick & place 실습 — venv

### 1. 실습 소스 배치 + 사전 점검

```bash
# 1) 실습 패키지 2개를 데모 워크스페이스로 (cobot2.zip 이 ~/Downloads 에 있다고 가정)
mkdir -p ~/cobot_demo_ws/src
cd ~/Downloads && unzip -q cobot2.zip
mv ~/Downloads/cobot2/pick_and_place_text ~/Downloads/cobot2/pick_and_place_voice \
   ~/cobot_demo_ws/src/

# 2) 사전 점검
command -v ros2                                  # → /opt/ros/jazzy/bin/ros2
ls ~/ros2_jazzy_test/resources/config.sh
ls ~/cobot_demo_ws/src/                          # → pick_and_place_text  pick_and_place_voice
```

`~/Downloads/cobot2` 는 §2 에서 od_msg 를 꺼내 쓰므로 아직 지우지 않는다.

### 2. 인터페이스 + bringup 스택 준비

이 실습은 워크스페이스 하나(`~/cobot_demo_ws`)만 쓴다 — 드라이버와 bringup 도 여기에 함께 둔다.
정식 워크스페이스(`~/cobot2_ws`)를 먼저 빌드해 둘 필요가 없다.

```bash
# 1) doosan-robot2 드라이버 (dsr_common2 / dsr_msgs2 / dsr_bringup2 / dsr_controller2 / dsr_description2 …)
git clone --depth 1 https://github.com/ROKEY-SPARK/doosan-robot2_jazzy.git \
  ~/cobot_demo_ws/src/doosan-robot2

# 2) 통합 bringup — 레포는 바깥에 두고 패키지 하나만 심볼릭 링크 (moveit 스택 제외)
git clone -b jazzy https://github.com/Seooooooogi/M0609_RG2_Integration ~/M0609_RG2_Integration
ln -sfn ~/M0609_RG2_Integration/src/m0609_rg2_bringup ~/cobot_demo_ws/src/m0609_rg2_bringup

# 3) OnRobot RG2 그리퍼 드라이버 — 커밋 고정
git clone https://github.com/ABC-iRobotics/onrobot-ros2 ~/cobot_demo_ws/src/onrobot-ros2
git -C ~/cobot_demo_ws/src/onrobot-ros2 checkout c6e390313e831a2e54a0ad5894b2911cc360a16a

# 4) od_msg — cobot2 소스에서 복사
cp -r ~/Downloads/cobot2/yolo_container/od_msg ~/cobot_demo_ws/src/

# 5) DSR 에뮬레이터 이미지 (mode:=virtual 이 이 컨테이너를 띄운다)
docker pull doosanrobot/dsr_emulator:3.0.1

# 6) RealSense udev 규칙 — 카메라 필수. ROS 의 realsense2_camera 패키지는 udev 규칙을 깔지
#    않아, 없으면 USB autosuspend 로 스트리밍 중 장치가 재워져 "VIDIOC_QBUF ... No such device"
#    가 폭주하고 프레임이 안 나온다(IMU 접근 권한도 함께 막힘). 규칙이 그 둘을 다 푼다.
sudo curl -fsSL https://raw.githubusercontent.com/IntelRealSense/librealsense/master/config/99-realsense-libusb.rules \
  -o /etc/udev/rules.d/99-realsense-libusb.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
# 적용 후 카메라 USB 를 뽑았다 다시 꽂는다.

# 검증
ls ~/cobot_demo_ws/src/
# → doosan-robot2  m0609_rg2_bringup  od_msg  onrobot-ros2
#   pick_and_place_text  pick_and_place_voice
test -f /etc/udev/rules.d/99-realsense-libusb.rules && echo "udev 규칙 OK"
```

fork(`ROKEY-SPARK/doosan-robot2_jazzy`)에는 `DSR_ROBOT2.py` 의 서비스 클래스명·prefix 패치가 이미
반영돼 있다 — 별도 sed 절차가 필요 없다.

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

wakeword 캡처는 **sounddevice** 로 한다(이 하드웨어의 디지털 마이크는 PyAudio 로는 무음으로
잡힌다). 그래서 이 확인도 실제 실행과 같은 backend·같은 함수(`resolve_input_device()`)·같은
16kHz 로 연다 — PyAudio 로 확인하면 통과해도 실행 때 조용히 실패할 수 있다.

```bash
# 장치 확인 — 실행이 실제로 쓰는 경로(sounddevice 16kHz)로 연다
~/cobot_demo_ws/.venv/bin/python -c "
import os, sys
sys.path.insert(0, os.path.expanduser('~/cobot_demo_ws/src/pick_and_place_voice'))
from voice_processing.audio_device import resolve_input_device
import sounddevice as sd
idx = resolve_input_device()
info = sd.query_devices(idx if idx is not None else None, 'input')
print('device:', idx, info['name'], '| rate:', int(info['default_samplerate']))
with sd.InputStream(samplerate=16000, channels=1, dtype='int16', blocksize=1280, device=idx) as s:
    s.read(1280)
print('sounddevice open/read/close OK')
"
```

다른 기기 사용 시 — 입력 장치 목록에서 인덱스를 골라 `VOICE_MIC_DEVICE` 로 지정
(ALSA 이름 `hw:1,7` 또는 정수 인덱스. sounddevice 는 둘 다 받는다):

```bash
~/cobot_demo_ws/.venv/bin/python -c "
import sounddevice as sd
for i, d in enumerate(sd.query_devices()):
    if d['max_input_channels'] > 0:
        print(i, d['name'], int(d['default_samplerate']), d['max_input_channels'])
"
# 예: export VOICE_MIC_DEVICE='hw:1,7'
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

# DSR 전용 apt 의존 + CycloneDDS RMW.
# config.sh 가 기본 RMW 를 cyclonedds 로 고정하므로 rmw-cyclonedds-cpp 가 없으면
# colcon 이 "Could not find ROS middleware implementation" 로 실패한다.
sudo apt-get install -y ros-jazzy-rmw-cyclonedds-cpp \
  ros-jazzy-velocity-controllers ros-jazzy-eigen3-cmake-module

cd ~/cobot_demo_ws
rosdep update
# skip-keys 사유:
#   librealsense2                      — apt 로 까는 네이티브 SDK, ROS rosdep 키가 아니다
#   message_generation/message_runtime — onrobot-ros2 의 ROS1 잔재, jazzy 에 해당 규칙이 없다
rosdep install --from-paths src --ignore-src --rosdistro jazzy \
  --skip-keys="librealsense2 message_generation message_runtime" -y

colcon build

# 검증
source /opt/ros/jazzy/setup.bash
source ~/cobot_demo_ws/install/setup.bash
ros2 pkg list | grep -E "m0609_rg2_bringup|onrobot_rg_control|dsr_bringup2|pick_and_place_(text|voice)|od_msg"
ls ~/cobot_demo_ws/install/pick_and_place_voice/share/pick_and_place_voice/resource/yolov8n_tools_0122.pt

# DSR_ROBOT2 는 import 시점에 모듈 본문이 곧바로 g_node.create_client(...) 를 실행한다.
# 그 g_node 는 DR_init.__dsr__node 이고 기본값이 None 이라, 노드를 먼저 세우지 않고 그냥
# import 하면 'NoneType' object has no attribute 'create_client' 로 죽는다. 실제 노드
# (robot_move.py / robot_control.py)는 import 전에 아래 순서로 노드를 세운다 — 같은 손잡기를 재현한다.
python3 -c "
import rclpy, DR_init
rclpy.init()
DR_init.__dsr__id = 'dsr01'; DR_init.__dsr__model = 'm0609'
DR_init.__dsr__node = rclpy.create_node('iface_smoke', namespace='dsr01')
from DSR_ROBOT2 import movej
from od_msg.srv import SrvDepthPosition
print('interface imports OK')
"
```

### 8. 실행 — text 데모

```bash
# 터미널 1 — 드라이버 (bringup · 카메라 없이 — 카메라는 다음 블록에서 따로)
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_demo_ws/install/setup.bash
ros2 launch m0609_rg2_bringup bringup.launch.py mode:=virtual
# 실로봇: ros2 launch m0609_rg2_bringup bringup.launch.py mode:=real host:=192.168.1.100
```

```bash
# 터미널 1-카메라 — RealSense 직접 기동 (bringup 이 camera:=false 라 카메라는 이걸로 따로)
# -r __ns:=/ -r __node:=camera 가 /camera/camera/* 를 /camera/* 로 맞추는 인자.
# pointcloud.stream_filter 2 = color 텍스처 — 미지정 시 0(ANY)이라 cloud 에 rgb 가 없어 RViz RGB8 표시가 error.
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
ros2 run realsense2_camera realsense2_camera_node --ros-args \
  -r __ns:=/ -r __node:=camera \
  -p enable_color:=true -p enable_depth:=true \
  -p depth_module.depth_profile:=848x480x30 -p rgb_camera.color_profile:=1280x720x30 \
  -p align_depth.enable:=true -p enable_rgbd:=true -p enable_sync:=true \
  -p pointcloud.enable:=true -p pointcloud.stream_filter:=2 -p initial_reset:=true
```

```bash
# 터미널 2 — YOLO depth 서비스 노드 (detection, venv)
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_demo_ws/install/setup.bash
source ~/cobot_demo_ws/.venv/bin/activate
# activate 만으로는 부족하다 — ros2 run 이 띄우는 노드는 시스템 python shebang 으로 뜨므로
# venv 패키지를 보려면 PYTHONPATH 도 함께 넣는다.
export PYTHONPATH="$(ls -d ~/cobot_demo_ws/.venv/lib/python*/site-packages):$PYTHONPATH"
ros2 run pick_and_place_text detection
# 카메라 토픽 배선 — img_node 는 /camera/color/image_raw 등을 절대 경로로 구독하므로 기동 인자가
# 필요 없다. 예전 자료의 '--ros-args -r img_node:__ns:=/camera' 를 붙여도 결과는 같다(절대 이름은
# 네임스페이스 remap 의 영향을 받지 않는다). 배포본이 구본이라 상대 이름을 구독한다면 그 인자가
# 있어야 동작한다 — 그때는 'img_node:' 접두사를 반드시 붙일 것. 빼고 -r __ns:=/camera 로 쓰면
# 같은 프로세스의 detection 노드까지 옮겨져 robot_move 가 부르는 /get_3d_position 이 끊긴다.
# → YOLO 로드 → "Waiting for client's call..." (에뮬레이터 없으면 카메라 토픽 대기 = 정상)
# remap 을 빠뜨려도 노드는 에러 없이 그냥 뜬다 — 토픽만 조용히 비어 있다.
```

```bash
# 터미널 3 — 오케스트레이터 (robot_move, venv)
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_demo_ws/install/setup.bash
source ~/cobot_demo_ws/.venv/bin/activate
# activate 만으로는 부족하다 — ros2 run 이 띄우는 노드는 시스템 python shebang 으로 뜨므로
# venv 패키지를 보려면 PYTHONPATH 도 함께 넣는다.
export PYTHONPATH="$(ls -d ~/cobot_demo_ws/.venv/lib/python*/site-packages):$PYTHONPATH"
ros2 run pick_and_place_text robot_move
# → DSR 노드 초기화(_robot_id=dsr01) → MoveJ 서비스 대기. 에뮬레이터 없이 "waiting..." 반복 = 정상 [HW/emulator]
# → OnRobot 그리퍼는 import 시 192.168.1.1:502 Modbus 연결 시도 — 실패 시 가상 모드 진입 [HW]
```

### 9. 실행 — voice 데모

```bash
# 터미널 1 — 드라이버 (bringup · 카메라 없이 — 카메라는 다음 블록에서 따로)
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_demo_ws/install/setup.bash
ros2 launch m0609_rg2_bringup bringup.launch.py mode:=virtual
```

```bash
# 터미널 1-카메라 — RealSense 직접 기동 (bringup 이 camera:=false 라 카메라는 이걸로 따로)
# -r __ns:=/ -r __node:=camera 가 /camera/camera/* 를 /camera/* 로 맞추는 인자.
# pointcloud.stream_filter 2 = color 텍스처 — 미지정 시 0(ANY)이라 cloud 에 rgb 가 없어 RViz RGB8 표시가 error.
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
ros2 run realsense2_camera realsense2_camera_node --ros-args \
  -r __ns:=/ -r __node:=camera \
  -p enable_color:=true -p enable_depth:=true \
  -p depth_module.depth_profile:=848x480x30 -p rgb_camera.color_profile:=1280x720x30 \
  -p align_depth.enable:=true -p enable_rgbd:=true -p enable_sync:=true \
  -p pointcloud.enable:=true -p pointcloud.stream_filter:=2 -p initial_reset:=true
```

```bash
# 터미널 2 — YOLO depth 서비스 노드 (object_detection, venv)
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_demo_ws/install/setup.bash
source ~/cobot_demo_ws/.venv/bin/activate
# activate 만으로는 부족하다 — ros2 run 이 띄우는 노드는 시스템 python shebang 으로 뜨므로
# venv 패키지를 보려면 PYTHONPATH 도 함께 넣는다.
export PYTHONPATH="$(ls -d ~/cobot_demo_ws/.venv/lib/python*/site-packages):$PYTHONPATH"
ros2 run pick_and_place_voice object_detection
# 카메라 토픽 배선은 §8 터미널 2 와 동일 — img_node 가 /camera/color/image_raw 등을 절대 경로로
# 구독하므로 기동 인자가 필요 없다. 배포본이 구본이면 '--ros-args -r img_node:__ns:=/camera' 를
# 붙인다. robot_control 이 부르는 /get_3d_position 은 어느 쪽이든 루트에 그대로 남는다.
# → YOLO 로드 → "[img_node]: Waiting for client's call..." (카메라 토픽 대기 = 정상)
```

```bash
# 터미널 3 — 음성 명령 처리 (get_keyword, venv)
# OpenAI 소비처는 이 노드뿐(ChatOpenAI + Whisper STT) — 키는 §6 의 .env 가 빌드에 내장돼 있어 export 불요
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_demo_ws/install/setup.bash
source ~/cobot_demo_ws/.venv/bin/activate
# activate 만으로는 부족하다 — ros2 run 이 띄우는 노드는 시스템 python shebang 으로 뜨므로
# venv 패키지를 보려면 PYTHONPATH 도 함께 넣는다.
export PYTHONPATH="$(ls -d ~/cobot_demo_ws/.venv/lib/python*/site-packages):$PYTHONPATH"
ros2 run pick_and_place_voice get_keyword
# → "MicRecorderNode initialized." → "wait for client's request..." (wakeword "Hello Rokey" 대기)
```

```bash
# 터미널 4 — 로봇 동작 (robot_control, venv)
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_demo_ws/install/setup.bash
source ~/cobot_demo_ws/.venv/bin/activate
# activate 만으로는 부족하다 — ros2 run 이 띄우는 노드는 시스템 python shebang 으로 뜨므로
# venv 패키지를 보려면 PYTHONPATH 도 함께 넣는다.
export PYTHONPATH="$(ls -d ~/cobot_demo_ws/.venv/lib/python*/site-packages):$PYTHONPATH"
ros2 run pick_and_place_voice robot_control
```

### 10. 정리 (teardown)

```bash
docker rm -f dsr01_emulator 2>/dev/null || true
rm -rf ~/cobot_demo_ws ~/M0609_RG2_Integration
```
