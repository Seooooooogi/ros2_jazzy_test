# venv 기반 pick & place 실습 데모 — 설계 (Design Spec)

- **날짜**: 2026-06-26
- **상태**: Draft (user review 대기)
- **관련**: `docs/decisions/` ADR-008 (host venv 폐기), 컨테이너 데모 (`containers/`), 외부 소스 `~/cobot_ws/src/cobot2` (이 레포 비추적)

---

## 1. 목적 (Goal)

**컨테이너 사용 유무의 효과를 학생에게 체감시키는 교육용 대비(contrast) 실습.**

- **컨테이너 방식** (현행 정식 경로): `voice-processing` 컨테이너 + `yolo-detection` 컨테이너 + host `robot_control` 마이크로서비스. 기동 = `bringup.sh` + `docker compose up -d` 수준의 몇 줄.
- **비컨테이너 방식** (본 데모): 모놀리식 원본 `pick_and_place_text` / `pick_and_place_voice` 를 host **venv** 로 직접 실행. 한 프로세스 묶음 안에 perception + motion (+ voice) 전부.
- 학생이 **셋업·실행 명령을 한 줄씩 직접 타이핑**하며, 컨테이너 이미지가 대신 구워주던 작업량(의존성 설치, numpy 핀, openwakeword 우회, 네임스페이스 충돌 회피, 멀티 터미널 기동)을 눈으로 관찰.

## 2. 비목표 (Non-goals)

- **정식 설치 흐름 변경 없음** — `install.sh` / `setup-app.sh` 비침투. 컨테이너가 정식 경로라는 ADR-008 결정을 유지. 본 데모는 그 결정의 **대비 사례**이지 번복이 아님.
- **오케스트레이션 셸 스크립트로 자동화하지 않음** — 한 줄 실행 스크립트(`setup-venv-demo.sh` 등)는 학습 가치를 무너뜨림. 산출물은 "읽고 따라치는 문서".
- **새 알고리즘/기능 추가 없음** — 기존 모놀리식 노드를 host venv 에서 "돌아가게" 만드는 범위까지.
- **`uv` / lock 기반 재현 환경 구축 아님** — 본 데모는 정식 재현 환경이 아닌 교육 아티팩트. plain `venv` + `pip` 가 컨테이너 Dockerfile 과 동일해 더 투명.

## 3. 확정된 사용자 결정

| 항목 | 결정 |
|------|------|
| 실행 범위 | 에뮬레이터 기본(`mode:=virtual`), 카메라·마이크 실물. 실로봇은 bringup 한 단계만 교체 |
| 통합 범위 | 독립 교육용 아티팩트 (정식 설치 흐름 비침투) |
| 소스 취급 | cobot2 두 패키지 **in-place 수정 허용** (원본 비추적이라 git 반영은 안 됨) |
| 산출물 | line-by-line 실습 가이드 `LAB.md` — **셋업·실행 모두** 명령 전부 노출 |
| 도구 | plain `python3 -m venv` + `pip` (컨테이너와 동일, uv 불요) |
| 복잡 명령 | `mv`/`sed`/`python -c` 까지 전부 inline 노출 (투명성 우선) |
| 통합 접근 | **A. 컨테이너 레시피 미러링** (isolated overlay + 통합 venv + PYTHONPATH 주입) |
| 충돌 처리 | voice 번들 패키지 **rename** (`ppv_*`) — source 순서 의존 불변식을 구조적으로 제거 |

## 4. 아키텍처

네 개의 산출물. 데모 실행 산출물은 `~/.cobot2_venv_demo/` 로 격리 → teardown 가능, 정식 설치 비오염.

```
ros2_jazzy_test/                          # 이 레포 (추적됨)
  scripts/venv-demo/
    LAB.md                                # ★ 실습 가이드 (Part A 셋업 + Part B 실행, 전 명령 노출)
    requirements.txt                      # 핀 목록 (컨테이너 미러) — 대조/참고용
  containers/voice-processing/oww_models/ # (기존) openwakeword feature 모델 — LAB 가 재사용
  README.md                               # 데모 진입점 링크 + 컨테이너 vs venv 대비 한 단락

~/.cobot2_venv_demo/                       # 데모 전용 격리 영역 (비추적, rm -rf 로 teardown)
  venv/                                   # python3 -m venv --system-site-packages (단일 통합)
  ws/                                     # 두 패키지만 빌드한 isolated colcon overlay
    install/

~/cobot_ws/src/cobot2/                     # 외부 소스 (in-place 수정 허용, 비추적)
  pick_and_place_text/                    # COLCON_IGNORE 제거 (rename 불요)
  pick_and_place_voice/                   # COLCON_IGNORE 제거 + 번들 3개 rename(ppv_*) + 마이크 fix
```

**구성요소 책임**

- **데모 overlay 워크스페이스** (`~/.cobot2_venv_demo/ws`): 두 패키지를 isolated install prefix 로 colcon 빌드(system python). DSR(`DSR_ROBOT2`/`DR_init`, `~/cobot_ws/install/dsr_common2`)·`od_msg`(`~/cobot_ws/install/od_msg`)는 host 빌드본 재사용 — 33개 DSR 재빌드 없음.
- **통합 venv** (`~/.cobot2_venv_demo/venv`): `--system-site-packages` 로 ROS python(`rclpy`/`cv_bridge`/`sensor_msgs`/`std_srvs`) 공유. 그 위에 application pip 의존을 설치(§6). text·voice 의존을 한 venv 가 모두 커버.
- **실행 (LAB.md Part B)**: 노드마다 별도 터미널. `config.sh`(RMW/도메인, R8) + ROS underlay + cobot_ws overlay + 데모 overlay 를 source 하고 venv site-packages 를 `PYTHONPATH` 앞에 주입 후 `ros2 run` — `containers/entrypoint.sh` 와 동일한 검증된 패턴.
- **패키지 rename (voice)**: §5.

### 4.1 실행 메커니즘 근거 (왜 `ros2 run` + PYTHONPATH 주입인가)

colcon 빌드는 system python 으로 수행 → ament console_script shebang 이 `/usr/bin/python3` 로 고정. venv python 은 동일 인터프리터(3.12)의 심볼릭이라, **venv site-packages 를 `PYTHONPATH` 에 얹기만 하면** system-python shebang 스크립트가 torch/ultralytics 등을 import 할 수 있다. `activate` 불필요(shebang 이 우선). 이 패턴은 `containers/entrypoint.sh` 가 컨테이너에서 동일하게 사용·검증.

## 5. 패키지 rename 명세 (voice 패키지만)

**근거**: `pick_and_place_voice` 는 generic top-level 패키지 3개(`robot_control`/`object_detection`/`voice_processing`)를 번들. 이 중 `robot_control` 은 host `~/cobot_ws/install/robot_control`(마이크로서비스판)과 **python import 네임스페이스 충돌**. 나머지 둘도 동일 아키텍처가 같은 이름을 쓰는 한 잠재 지뢰. rename 으로 source 순서 의존 없이 구조적 회피. (교육 포인트: 컨테이너는 파일시스템 격리라 generic 이름 충돌이 무관 / 공유 host 는 namespacing 필수.)

**rename 매핑**: `robot_control → ppv_robot_control`, `object_detection → ppv_object_detection`, `voice_processing → ppv_voice_processing`

**편집 대상 (전부 열거)**:

1. 디렉토리 3개 `mv` (`pick_and_place_voice/{robot_control,object_detection,voice_processing}`).
2. import 교정 6줄:
   - `ppv_robot_control/robot_control.py:13` — `from robot_control.onrobot import RG`
   - `ppv_object_detection/detection.py:8` — `from object_detection.realsense import ImgNode`
   - `ppv_object_detection/detection.py:9` — `from object_detection.yolo import YoloModel`
   - `ppv_voice_processing/get_keyword.py:15` — `from voice_processing.MicController import ...`
   - `ppv_voice_processing/get_keyword.py:17` — `from voice_processing.wakeup_word import WakeupWord`
   - `ppv_voice_processing/get_keyword.py:18` — `from voice_processing.stt import STT`
3. `setup.py`:
   - `find_packages(include=['robot_control','voice_processing','object_detection'])` → `ppv_*`
   - `entry_points` 모듈 경로 3줄: `robot_control.robot_control:main` → `ppv_robot_control.robot_control:main`, `object_detection.detection:main` → `ppv_object_detection.detection:main`, `voice_processing.get_keyword:main` → `ppv_voice_processing.get_keyword:main` (좌측 실행파일명 `robot_control`/`object_detection`/`get_keyword` 는 유지 — `ros2 run` 이 패키지로 구분).

> **주의(비충돌 false-positive 방지 — 전역 `sed` 금지)**: 다음은 패키지 참조가 아니므로 **변경 금지**:
> - 메서드/호출: `robot_control.py:92` `def robot_control(self)`, `:183` `node.robot_control()`
> - **ROS 노드명 문자열**: `robot_control.py:34` `rclpy.create_node("robot_control_node", ...)`, `detection.py:18` `super().__init__('object_detection_node')` — 건드리면 namespace/서비스 discovery 가 깨짐(R5)
> - 로그 문자열 "object_detection node", entry_points 좌측 실행파일명(`robot_control`/`object_detection`/`get_keyword`)
>
> 편집은 **line-targeted** 로만: import 6줄(`robot_control.py:13`, `detection.py:8-9`, `get_keyword.py:15/17/18`) + `setup.py`(find_packages, entry_points 우측 모듈경로). 전역 `sed s/<name>/ppv_<name>/g` 는 위 노드명 문자열·실행파일명까지 오염하므로 **금지**.

`pick_and_place_text` 는 전부 `pick_and_place_text.*` 네임스페이스라 **rename 불요**.

## 6. 의존성 레시피 (두 컨테이너 Dockerfile 합성 + 모놀리식 추가분)

모놀리식 노드는 한 프로세스에 perception+motion(+voice) 을 묶으므로, **`yolo-detection` 레시피 ∪ `voice-processing` 레시피 + 컨테이너에 없던 항목**이 필요.

**파생 출처**:
- yolo 레시피: `containers/yolo-detection/Dockerfile` (torch cu128 / `ultralytics<9` / `opencv-python<4.10` / `numpy<2` 재핀)
- voice 레시피: `containers/voice-processing/Dockerfile` (`langchain<2`/`langchain-openai<2`/`openai<3`/`pyaudio`/`sounddevice`/`scipy<1.18`/`python-dotenv` + openwakeword 0.6.0 `--no-deps` + ai-edge-litert shim + feature 모델 + `numpy<2` 재핀)
- 추가분: `pymodbus`(그리퍼 Modbus — 두 컨테이너 어디에도 없음. 컨테이너는 그리퍼를 host robot_control 이 구동), `portaudio19-dev`/`libsndfile1`(pyaudio/soundfile 빌드 — 컨테이너는 이미지에 포함).

**순서 (numpy<2 가 마지막에 이기는 게 핵심)**:

```bash
# (0) 시스템 빌드 의존 — pyaudio 컴파일에 portaudio19-dev 필수 (컨테이너는 이미지에 구워둠).
#     libsndfile1 은 컨테이너 이미지 미러일 뿐 본 코드 소비처 없음(soundfile 미사용) — 생략 가능.
sudo apt install -y portaudio19-dev libsndfile1

# (1) venv 생성 + ROS python 공유
python3 -m venv --system-site-packages ~/.cobot2_venv_demo/venv
source ~/.cobot2_venv_demo/venv/bin/activate
pip install --upgrade pip

# (2) [yolo 레시피] torch 최우선 (가장 무거움) — cu128 = resources/config.sh CUDA_VERSION 기준
pip install --index-url https://download.pytorch.org/whl/cu128 torch torchvision
pip install "ultralytics<9"
pip install "opencv-python<4.10"

# (3) [voice 레시피] LLM/음성
pip install "langchain<2" "langchain-openai<2" "openai<3" pyaudio sounddevice "scipy<1.18" python-dotenv

# (4) [모놀리식 추가분] 그리퍼 Modbus
pip install pymodbus

# (5) openwakeword — Python 3.12 우회 (tflite-runtime cp312 wheel 부재 → ai-edge-litert shim)
pip install --no-deps "openwakeword==0.6.0"
pip install "onnxruntime<2,>=1.10.0" "tqdm<5,>=4.0" "scikit-learn<2,>=1" "requests<3,>=2.0" "ai-edge-litert>=2.0.2,<3"
python3 -c "import os,ai_edge_litert as a; d=os.path.join(os.path.dirname(os.path.dirname(a.__file__)),'tflite_runtime'); os.makedirs(d,exist_ok=True); open(os.path.join(d,'__init__.py'),'w').close(); open(os.path.join(d,'interpreter.py'),'w').write('from ai_edge_litert.interpreter import Interpreter  # noqa: F401\n')"
# feature 모델(melspectrogram/embedding/VAD) — 레포 vendoring 본 재사용
OWW_DIR="$(python3 -c 'import os,openwakeword;print(os.path.join(os.path.dirname(openwakeword.__file__),"resources","models"))')"
mkdir -p "$OWW_DIR" && cp ~/ros2_jazzy_test/containers/voice-processing/oww_models/* "$OWW_DIR"/
# TFL3 매직바이트(offset 4) 검증 — 손상본 유입 차단 (Dockerfile 과 동일)
python3 -c "import os; d='$OWW_DIR'; [ (open(os.path.join(d,f),'rb').read(8)[4:8]==b'TFL3') or (_ for _ in ()).throw(SystemExit('corrupt tflite: '+f)) for f in os.listdir(d) if f.endswith('.tflite')]; print('feature models TFL3 OK')"

# (6) ★ numpy<2 재핀 — 반드시 마지막 + import 검증
pip install --force-reinstall "numpy<2"
python3 -c "import numpy,torch,ultralytics,cv2,langchain,langchain_openai,openai,pyaudio,sounddevice,scipy,openwakeword,ai_edge_litert,tflite_runtime.interpreter,pymodbus; assert numpy.__version__.startswith('1.'), numpy.__version__; print('deps OK', numpy.__version__)"
```

**text 전용 실습 분기**: voice 전용 의존만 생략 — (3) 의 LLM/음성(`langchain`/`langchain-openai`/`openai`/`pyaudio`/`sounddevice`/`python-dotenv`)과 (5) openwakeword 블록. **단 `scipy<1.18` 는 text 도 필수** (`robot_move.py:4` 가 `scipy.spatial.transform.Rotation` import; 무핀 `scipy>=1.18` 은 numpy>=2 를 요구해 numpy<2 재핀과 충돌). 따라서 text 분기 = `torch torchvision` + `ultralytics<9` + `opencv-python<4.10` + **`"scipy<1.18"`** + `pymodbus` + `numpy<2` 재핀. LAB.md 에 분기 표기.

> 각 명령 경로의 python 버전(`python3.12`)은 noble 기준. LAB.md 는 glob(`python*/site-packages`)으로 버전 비종속 표기.

## 7. 명령 흐름 — Part A 셋업 (LAB.md, line-by-line)

한 터미널에서 순서대로. 각 줄마다 "예상 결과" 주석.

- **A1. 원본 활성화** — `pick_and_place_text` / `pick_and_place_voice` 의 `COLCON_IGNORE` 제거 (`rm` 2줄).
- **A2. voice rename** — §5 의 `mv` 3줄 + `sed -i` 6줄(import) + `sed -i` (setup.py find_packages/entry_points). 마이크 fix(§9 R2) 동반.
- **A3. venv 생성** — §6 (1).
- **A4. pip 설치** — §6 (0)(2)–(6). 각 줄 관찰 (특히 numpy<2 재핀에서 다운그레이드 로그 확인).
- **A4b. 에셋 스테이징 (voice 만, 필수)** — voice 패키지 `resource/` 엔 YOLO 가중치·핸드아이 보정행렬이 **없음**(원본 누락, R7). colcon 빌드 **전에** text 패키지본 복사:
  ```bash
  cp ~/cobot_ws/src/cobot2/pick_and_place_text/resource/yolov8n_tools_0122.pt ~/cobot_ws/src/cobot2/pick_and_place_voice/resource/
  cp ~/cobot_ws/src/cobot2/pick_and_place_text/resource/T_gripper2camera.npy  ~/cobot_ws/src/cobot2/pick_and_place_voice/resource/
  ```
  (없으면 `object_detection` 노드가 `__init__` 에서 즉시 FileNotFoundError, `robot_control` 은 좌표변환 시 크래시.)
- **A5. colcon 빌드** — 두 패키지만 isolated prefix 로 (**빌드는 system python 으로** — venv `deactivate` 선행, §4.1):
  ```bash
  deactivate                                                       # console_script shebang 을 system python 으로 고정
  set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a     # RMW=cyclonedds / ROS_DOMAIN_ID=42 (R8)
  source /opt/ros/jazzy/setup.bash
  source ~/cobot_ws/install/setup.bash                             # DSR + od_msg underlay
  mkdir -p ~/.cobot2_venv_demo/ws/src
  ln -sfn ~/cobot_ws/src/cobot2/pick_and_place_text  ~/.cobot2_venv_demo/ws/src/pick_and_place_text
  ln -sfn ~/cobot_ws/src/cobot2/pick_and_place_voice ~/.cobot2_venv_demo/ws/src/pick_and_place_voice
  cd ~/.cobot2_venv_demo/ws && colcon build
  ```

## 8. 명령 흐름 — Part B 실행 (LAB.md, terminal-by-terminal literal)

노드마다 별도 터미널. 매 터미널 prologue **첫 줄 = `config.sh`**(RMW/도메인, R8) → bringup 터미널은 source 3종, venv 노드 터미널은 source 4종 + PYTHONPATH. **전 명령 노출.**

**text 데모 — 터미널 3개**

```bash
# ── 터미널 1: 로봇 드라이버 + 카메라 (host, 에뮬레이터 기본) ──
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a     # RMW=cyclonedds / ROS_DOMAIN_ID=42 (R8)
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
ros2 launch cobot2_bringup bringup_all.launch.py mode:=virtual
#  실로봇: ros2 launch cobot2_bringup bringup_all.launch.py mode:=real host:=192.168.1.100

# ── 터미널 2: YOLO depth 서비스 노드 (venv) ──
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
source ~/.cobot2_venv_demo/ws/install/setup.bash
export PYTHONPATH="$(ls -d ~/.cobot2_venv_demo/venv/lib/python*/site-packages):$PYTHONPATH"
ros2 run pick_and_place_text detection

# ── 터미널 3: pick&place 오케스트레이터 (venv) ──
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
source ~/.cobot2_venv_demo/ws/install/setup.bash
export PYTHONPATH="$(ls -d ~/.cobot2_venv_demo/venv/lib/python*/site-packages):$PYTHONPATH"
ros2 run pick_and_place_text robot_move
```

**voice 데모 — 터미널 4개**: 터미널 1(bringup, 위와 동일) / 터미널 2(`object_detection`) / 터미널 3(`get_keyword`) / 터미널 4(`robot_control`). venv 노드(2–4) prologue = **config.sh + ros + cobot_ws + 데모 overlay = source 4줄 + PYTHONPATH** (text 데모와 동형). 추가로:
- **OPENAI 키는 `get_keyword` 터미널(3)** 에서 `export OPENAI_API_KEY=...`. 실제 소비처 = `get_keyword.py`(ChatOpenAI/STT); **`robot_control` 은 `/get_keyword` 서비스만 호출하며 OpenAI 미사용** → 키를 robot_control 터미널에만 두면 voice 실패.
- `.env` 대안은 **설치된 share 경로**(`get_package_share_directory` → `share/pick_and_place_voice/resource/.env`)를 읽음 → 소스 `resource/` 에 `.env` 를 두려면 재빌드 필요. 셸 `export` 권장.
- 마이크: §9 R2 fix 전제.

노드 실행파일명: text=`detection`,`robot_move` / voice=`object_detection`,`get_keyword`,`robot_control`.

**대비 마무리**: "이 3–4 터미널 · 다수 명령 = 컨테이너였다면 `bash containers/bringup.sh` + `docker compose up -d` 두 줄."

## 9. 알려진 리스크 / 필수 선결 (정직성)

- **R1 그리퍼 (Modbus)** — `RG(GRIPPER_NAME, "192.168.1.1", "502")` 가 모듈 로드 시 실 toolchanger 에 접속. 순수 에뮬(그리퍼 없음)에선 그리퍼 동작이 실패/저하. 실습실 실하드웨어면 정상. LAB.md 에 명시. (`pick_and_place_text/.../robot_move.py`, `pick_and_place_voice/.../robot_control.py`)
- **R2 마이크 (voice, 필수 선결)** — 모놀리식 `voice_processing` 엔 컨테이너에 넣었던 `audio_device.py`(host DMIC 클리핑 회피 — 16kHz 네이티브 입력 자동선택) 수정이 **없음** → 그대로면 wakeword 미응답 재현. 해소: 동일 fix 이식(컨테이너 `voice_container/voice_processing/voice_processing/audio_device.py` 패턴 — 경로에 `voice_processing` 2중첩 주의) 또는 device override. **writing-plans 에서 구체 명령 확정.**
- **R3 torch cu128 대용량 다운로드(수 GB)** — 최초 1회 시간/네트워크. ("컨테이너는 이미지 pull 로 끝" 대비 포인트.)
- **R4 numpy<2 는 반드시 마지막** + import 검증 — transitive 상향 시 ultralytics 런타임 실패.
- **R5 `ROBOT_ID="dsr01"`/`ROBOT_MODEL="m0609"` 하드코딩 ↔ bringup 일치** — bringup 의 model/name 이 노드 상수와 어긋나면 namespace 불일치로 서비스/토픽 미발견.
- **R6 host 선결 상태** — `~/cobot_ws/install` 에 DSR·od_msg·realsense 빌드본 존재 가정(정식 설치 완료 머신). 미충족 시 셋업 abort 안내.
- **R7 voice 패키지 에셋 누락 (필수 선결)** — `pick_and_place_voice/resource/` 에 YOLO 가중치 `yolov8n_tools_0122.pt`·핸드아이 보정 `T_gripper2camera.npy` 가 **없음**(원본 누락; 두 파일 모두 `pick_and_place_text/resource/` 에만 존재). `object_detection`(`yolo.py`)은 `__init__` 에서 `.pt` 를 즉시 로드 → 미존재 시 FileNotFoundError, `robot_control`(`robot_control.py`)은 좌표변환에서 `.npy` 로드 크래시. Part A4b 가 text 본 복사로 선해소.
- **R8 DDS/RMW/도메인 일치 (필수 선결)** — host bringup·컨테이너는 `resources/config.sh` 의 `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp`·`ROS_DOMAIN_ID=42`·`CYCLONEDDS_URI` 를 강제(`bringup_all.launch.py` docstring 이 config.sh source 를 기동 전제로 명시). venv 터미널이 이를 누락하면 ROS 기본(fastrtps/domain 0)으로 떨어져 host 토픽/서비스를 **조용히 미발견**(데모 hang). 모든 Part A5/B 터미널 prologue 첫 줄에 `set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a` 명시 — clean shell 이 dds-tuning `~/.bashrc` 관리 블록에 암묵 의존하지 않도록.

## 10. README 통합 (구현 범위)

`README.md` 에 짧은 진입점 추가 (구현 단계에서 편집):
- "컨테이너 없이 실행해 보기 (교육용 대비)" 한 단락 + `scripts/venv-demo/LAB.md` 링크.
- 컨테이너 방식(`bringup.sh` + `docker compose`) ↔ venv 방식(LAB.md 다수 단계) 대비 1–2줄.
- 정식 설치 경로가 아님을 명시(혼동 방지).

## 11. 성공 기준 (Success criteria)

1. 깨끗한 정식설치 머신에서 LAB.md 의 Part A 를 한 줄씩 따라치면 venv + overlay 빌드가 에러 없이 완료(§6 import 검증 통과).
2. Part B 로 **text 데모**가 에뮬레이터에서 노드 3개 기동 → YOLO depth 서비스 응답 + `robot_move` 가 가상 로봇 모션 수행(그리퍼 단계는 R1 조건부).
3. **voice 데모**가 (R2 fix 적용 시) wakeword "Hello Rokey" 탐지 → STT → LLM → 모션까지 연결.
4. 데모 산출물이 `~/.cobot2_venv_demo/` 에 격리 — `rm -rf` 로 완전 teardown, 정식 설치/컨테이너 무영향.
5. `install.sh`/`setup-app.sh` 무변경 확인.

## 12. Teardown

```bash
rm -rf ~/.cobot2_venv_demo
# (선택) 원본 복구: cobot2 두 패키지 COLCON_IGNORE 재생성 + rename 되돌리기 — 비추적이라 git 무관
```

---

### 부록 A. 충돌 표면 실측 (2026-06-26)

- host `~/cobot_ws/install` 에 존재하는 충돌 후보: `robot_control` (마이크로서비스판, `lib/robot_control` 존재). `object_detection`/`voice_processing` 은 host install 에 **없음**(컨테이너 전용).
- 따라서 **현 시점 실제 host 충돌은 `robot_control` 하나** — 단 generic 이름 3개 모두 rename(일관성·미래 지뢰 제거).
- `pick_and_place_text` 는 generic 번들 import 없음 — 전부 `pick_and_place_text.*`.
