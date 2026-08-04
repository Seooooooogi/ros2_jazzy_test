# 교육생 실습 경로 (Trainee Hands-on Path) — host venv → docker

## 목적 / 대상

초급 교육생이 **host 에서 먼저(venv, 즉시·단순) 실습 → 최종적으로 docker 컨테이너로 관리**하는 학습 arc.
docker-first 가 초급에 무리라는 판단에서, 하드웨어·GPU 작업은 host, 런타임 서비스(의존성 격리가 이득인 곳)는 container 로 졸업시킨다.
배경/근거는 [CONTAINER_VS_HOST.md](CONTAINER_VS_HOST.md) (왜 컨테이너인가 — 의존성 경계).

- **대상 머신**: 실기 노트북 ([실측] — DSR robot + RealSense + RG gripper + 마이크 부착).
- **GPU**: YOLO 학습/추론에 필요.

## 다음 세션 Claude 빠른 진입 (이 문서 = 실행형 runbook)

4단계를 순서대로. 각 단계 = `실행처 / env 셋업 / 실행 / 산출물 / 검증 / gotcha`. 아래 [치트시트](#claude-치트시트-복붙) 복붙 가능.

**확정 결정 (2026-06-25)**:
- Step 2 학습은 **host venv (A안)** — "학습 전용 dev venv". 운영(추론)만 컨테이너. 초급 host-first 취지.
- host 학습 venv 의 Python 은 **3.12** (`ai-edge-litert`/openwakeword cp312 전제). 이 fleet 의 system python 이 3.10 이면 **`uv venv --python 3.12`** 로 공급 (host system python 무변경).

**⚠ 선행 수정 1건 (Step 4 블로커)**:
- `corecode/VoiceProcessing/keyword_extraction.py:5`
  `from langchain.prompts import PromptTemplate` → `from langchain_core.prompts import PromptTemplate`
- 이유: 핀된 `langchain<2`(=1.3.x)에서 `langchain.prompts` 제거됨. **컨테이너/호스트 공통** 으로 깨짐 (host venv import smoke 에서 `ModuleNotFoundError` 실측). cobot2 앱 판은 이미 `langchain_core` 로 수정됨 — corecode 사본만 미반영.

## 공통 전제 (선행 — 이미 됐으면 skip)

- base 환경: `bash install.sh` (kernel/NVIDIA/Docker/ROS2/DDS tuning/static IP/corecode check, 10 step).
- 애플리케이션: `bash setup-app.sh` (`~/cobot2_ws` 워크스페이스 + yolo 이미지 빌드 + host voice Python 설치 `app-install.sh voice`). voice 는 컨테이너 아님 — host 직접 실행(ADR-027). OPENAI 키는 사용자가 `~/.config/cobot2/.env` 직접 생성(ADR-028).
- corecode 위치: `~/corecode` (사용자가 corecode.zip 을 홈에 풀어 배치 → install.sh step 10 이 확인). 레포엔 미포함(ADR-029).
- DDS: `resources/hostcfg.sh dds` 완료 (`~/.config/cyclonedds/cyclonedds.xml` — 컨테이너가 read-only mount).

---

## Step 1 — Calibration (host) → `T_gripper2camera.npy`

- **실행처**: host. DSR robot + RealSense + RG gripper(modbus `192.168.1.1`) **하드웨어 필수**. 컨테이너로 빼면 USB/네트워크/modbus passthrough 부담 → host 가 정답.
- **env**: host 의 ROS2 python (rclpy) + `pyrealsense2`/카메라 토픽 + `pymodbus`(onrobot) + numpy/scipy/opencv. (system-site-packages venv 또는 system python.)
- **실행** (`cd ~/corecode/Calibration_Tutorial`):
  1. `python data_recording.py` — 로봇 포즈 + 카메라 이미지 수집
  2. `python handeye_calibration.py` — 계산 → **`T_gripper2camera.npy`** (CWD 저장, `handeye_calibration.py:227`)
  3. `python verify.py` — npy 로드해 재투영 검증 (`verify.py:47`)
- **산출물**: `T_gripper2camera.npy` (gripper↔camera 변환). Step 3 객체 인식의 3D 좌표 변환에 사용.
- **검증**: `verify.py` 통과 (재투영 오차 육안 확인).
- **gotcha**: gripper(`onrobot.py`, pymodbus 3.x) **하드웨어 동작 검증 미완** (핸드오프 [실측] 플래그). 실로봇 운용 전 RG open/close/move 확인. (`onrobot.py` import smoke 는 PASS.)

## Step 2 — YOLO 모델 학습 (host venv, GPU) → `best.pt`

- **실행처**: host. GPU 만 있으면 됨 (로봇 무관).
- **env 셋업** (학습 전용 dev venv — 우리가 import smoke 로 검증한 스택; host system python 무변경):
  ```bash
  export UV_CACHE_DIR="$HOME/.cache/uv-lab"   # 선택: 캐시 격리
  uv venv --python 3.12 "$HOME/yolo-train-venv"
  VPY="$HOME/yolo-train-venv/bin/python"
  uv pip install --python "$VPY" \
    --index-strategy unsafe-best-match \
    --extra-index-url https://download.pytorch.org/whl/cu128 \
    torch torchvision
  uv pip install --python "$VPY" "ultralytics<9" "opencv-python<4.10" supervision
  uv pip install --python "$VPY" --reinstall-package numpy "numpy<2"   # ultralytics 호환 필수
  ```
  (cu128 핀이 필요하면 위 `--extra-index-url`; uv 가 PyPI 최신(다른 CUDA)을 고를 수 있으니 정확한 CUDA 검증이 목적이면 `--index-url` 로 강제. 학습/numpy 공존엔 무관.)
- **데이터**: 라벨링 데이터셋 (`data.yaml`). `OD_Tutorial/YOLO/data_download.ipynb` 는 `ROBOFLOW_API_KEY` 필요 (`.env`).
- **실행**: `cd ~/corecode/OD_Tutorial/YOLO_SIMPLE` (또는 `YOLO`) → 데이터 경로/epochs 조정 후 `"$VPY" train.py`.
  - `YOLO_SIMPLE/train.py`: `YOLO("yolov8n-det.pt")` · `data="datasets_seg/data.yaml"` · `name="..."`.
- **산출물**: `runs/detect/<name>/weights/best.pt` (ultralytics 표준 출력) → Step 3 모델.
- **검증** (우리 실측): `ultralytics` import OK, `torch.cuda.is_available()=True`. 데이터셋 있으면 실제 학습.

## Step 3 — 모델 → yolo 컨테이너, 객체 인식

- **모델 배치**: `best.pt` 를 host `containers/models/` 에 복사 (노드가 로드하는 리소스명으로):
  ```bash
  mkdir -p containers/models
  cp ~/corecode/OD_Tutorial/.../weights/best.pt containers/models/yolov8n_tools_0122.pt
  ```
  `docker-compose.yml` 의 yolo-detection 에 마운트 (주석 처리된 자리 활성화):
  ```yaml
  volumes:
    - ./models/yolov8n_tools_0122.pt:/ws/install/share/object_detection/resource/yolov8n_tools_0122.pt:ro
  ```
- **카메라 먼저** (host 소유): `ros2 launch realsense2_camera rs_launch.py align_depth.enable:=true`
- **컨테이너 기동**: `docker compose -f containers/docker-compose.yml up -d yolo-detection`
  (프로덕션 이미지 CMD 가 `object_detection` 노드 자동 실행. `od_msg`(SrvDepthPosition) 빌드는 setup-app/이미지 빌드에 포함.)
- **검증**: `ros2 service list | grep get_3d_position`, 카메라 토픽 구독 + 추론 로그(`docker logs -f yolo-detection`).

## Step 4 — host 에서 corecode 음성 스크립트 (voice = host, ADR-027)

- **선행**: 위 ⚠ `keyword_extraction.py` langchain_core 수정.
- **voice = host 직접 실행**: 마이크가 하드웨어 종속(ALSA `/dev/snd` + PortAudio)이라 컨테이너의 하드코딩 `asound.conf` + raw ALSA passthrough 가 머신마다 불안정 → voice 만 host 로 환원. host 앱 Python(portaudio + openwakeword + langchain + openai)은 `resources/app-install.sh voice`(setup-app 이 실행)가 system pip(`--break-system-packages`)로 설치.
- **실행** (`cd ~/corecode/VoiceProcessing`, host 터미널. wakeword 가 ROS import 하므로 먼저 overlay source):
  ```bash
  source /opt/ros/jazzy/setup.bash
  cd ~/corecode/VoiceProcessing
  ```
- **실행 순서**:
  1. `python3 mic_test.py` — 마이크 캡처 확인 (host `/dev/snd` + apt `libportaudio2`)
  2. `python3 wakeup_word.py` — wakeword 감지 (`hello_rokey_8332_32.tflite` corecode 동봉, `MODEL_NAME` 상대경로라 이 디렉토리서 실행)
  3. `python3 STT.py` — 녹음 → OpenAI whisper (`OPENAI_API_KEY` 를 환경에 export — corecode 스크립트는 자체 dotenv 사용. 통합 cobot2 voice 노드는 `~/.config/cobot2/.env` 사용, ADR-028)
  4. `python3 keyword_extraction.py` — langchain LLM 키워드 추출 (수정 후)
- **핵심 교훈**: pyaudio/sounddevice 가 요구하는 **PortAudio(system C 라이브러리)** + 마이크 `/dev/snd` 는 **host-native** 라, 컨테이너로 감싸면 `asound.conf`·ALSA passthrough 를 머신마다 맞춰야 해 깨지기 쉽다 → voice 는 host 직접 실행이 정답(ADR-027). host 는 apt `portaudio19-dev`/`libportaudio2` + system pip 로 그 경계를 자연스럽게 넘는다.
- **gotcha**: `wakeup_word.py` 는 `ament_index_python`(ROS2)도 import — host 에서 `source /opt/ros/jazzy/setup.bash` 후 실행해야 ROS overlay 가 보인다.

---

## 알려진 블로커 / 검증 상태 (2026-06-25 세션 smoke)

- **`langchain.prompts` (keyword_extraction)** — 수정 필요 (위). host/컨테이너 공통.
- **gripper 하드웨어 검증 미완** — Step 1 (핸드오프 [실측] 플래그).
- **smoke 결과 요약**: 전 corecode `.py` syntax(py_compile) PASS · `onrobot`/`ultralytics(yolo_train/eval)` import PASS · `keyword_extraction` import FAIL(langchain) · voice audio = portaudio 게이트(host apt `portaudio19-dev`/`libportaudio2` 로 해결, ADR-027).
- **로봇/카메라 없는 머신에서 실제 실행 가능한 건 Step 2(YOLO 학습)뿐** — 나머지는 하드웨어(robot/camera/mic) 부재로 실행 불가(코드 문제 아님).

## Claude 치트시트 (복붙)

```bash
# [Step 2] host 학습 venv (Python 3.12, host system 무변경)
uv venv --python 3.12 "$HOME/yolo-train-venv"
uv pip install --python "$HOME/yolo-train-venv/bin/python" \
  --index-strategy unsafe-best-match --extra-index-url https://download.pytorch.org/whl/cu128 torch torchvision
uv pip install --python "$HOME/yolo-train-venv/bin/python" "ultralytics<9" "opencv-python<4.10" supervision
uv pip install --python "$HOME/yolo-train-venv/bin/python" --reinstall-package numpy "numpy<2"

# [Step 3] 카메라 → yolo 컨테이너
ros2 launch realsense2_camera rs_launch.py align_depth.enable:=true
docker compose -f containers/docker-compose.yml up -d yolo-detection

# [Step 4] host 에서 corecode 음성 스크립트 (voice = host, ADR-027)
source /opt/ros/jazzy/setup.bash               # wakeup_word.py 의 ament_index_python
cd ~/corecode/VoiceProcessing
python3 mic_test.py                             # → python3 wakeup_word.py → STT.py → keyword_extraction.py
```

> 갱신 트리거: 실기에서 단계별 실행 검증 후 실측 명령/산출 경로 교정, langchain 수정 반영, 데이터셋 경로 확정 시.
