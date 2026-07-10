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
- 애플리케이션: `bash setup-app.sh` (`~/cobot_ws` 워크스페이스 + yolo/voice 이미지 + OPENAI key → voice `.env`).
- corecode 위치: `~/corecode` (사용자가 corecode.zip 을 홈에 풀어 배치 → install.sh step 10 이 확인). 레포엔 미포함(ADR-029).
- DDS: `resources/dds-tuning.sh` 완료 (`~/.config/cyclonedds/cyclonedds.xml` — 컨테이너가 read-only mount).

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

## Step 4 — voice 컨테이너에서 corecode 음성 스크립트

- **선행**: 위 ⚠ `keyword_extraction.py` langchain_core 수정.
- **컨테이너엔 corecode 스크립트가 없음** (이미지엔 cobot2 `voice_processing` 만). → corecode 스크립트를 컨테이너에 **넣어서** 실행. 컨테이너는 *환경*(portaudio + openwakeword + langchain + openai + `/dev/snd` + `.env`)을 제공.
- **기동 + 주입** (dev override = 노드 auto-run 끔(idle) → exec 자유):
  ```bash
  docker compose -f containers/docker-compose.yml -f containers/docker-compose.dev.yml up -d voice-processing
  docker cp ~/corecode/VoiceProcessing voice-processing:/opt/voice-lab
  docker exec -it voice-processing bash
  # ↓ 컨테이너 안에서 (cd /opt/voice-lab)
  ```
- **실행 순서** (`/opt/voice-lab`):
  1. `python mic_test.py` — 마이크 캡처 확인 (`/dev/snd` + portaudio = 컨테이너 제공)
  2. `python wakeup_word.py` — wakeword 감지 (`hello_rokey_8332_32.tflite` corecode 동봉, `MODEL_NAME` 상대경로라 이 디렉토리서 실행)
  3. `python STT.py` — 녹음 → OpenAI whisper (`OPENAI_API_KEY` = 컨테이너 `.env`)
  4. `python keyword_extraction.py` — langchain LLM 키워드 추출 (수정 후)
- **핵심 교훈**: pyaudio/sounddevice 가 요구하는 **PortAudio(system C 라이브러리)** 를 컨테이너가 이미지 안 `apt` + `/dev/snd` 매핑으로 해결 → **host venv 가 못 넘던 경계를 컨테이너가 넘음** (host 에선 `import sounddevice` → `PortAudio library not found`, pyaudio 는 `portaudio.h` 없어 빌드 실패 — 실측).
- **gotcha**: `wakeup_word.py` 는 `ament_index_python`(ROS2)도 import — 컨테이너엔 ROS 있어 OK (host 격리 venv 엔 없음).

---

## 알려진 블로커 / 검증 상태 (2026-06-25 세션 smoke)

- **`langchain.prompts` (keyword_extraction)** — 수정 필요 (위). host/컨테이너 공통.
- **gripper 하드웨어 검증 미완** — Step 1 (핸드오프 [실측] 플래그).
- **smoke 결과 요약**: 전 corecode `.py` syntax(py_compile) PASS · `onrobot`/`ultralytics(yolo_train/eval)` import PASS · `keyword_extraction` import FAIL(langchain) · voice audio = portaudio 게이트(컨테이너서 해결).
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

# [Step 4] voice 컨테이너(idle) + corecode 스크립트 주입
docker compose -f containers/docker-compose.yml -f containers/docker-compose.dev.yml up -d voice-processing
docker cp ~/corecode/VoiceProcessing voice-processing:/opt/voice-lab
docker exec -it voice-processing bash   # cd /opt/voice-lab && python mic_test.py ...
```

> 갱신 트리거: 실기에서 단계별 실행 검증 후 실측 명령/산출 경로 교정, langchain 수정 반영, 데이터셋 경로 확정 시.
