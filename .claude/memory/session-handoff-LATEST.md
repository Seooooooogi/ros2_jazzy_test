# Session Handoff — LATEST

> 매 세션 종료 전 `/session-checkpoint` 로 갱신. 글로벌 `SessionStart` hook 이 자동 로드.
> Forward-looking only — 본 세션에서 한 일이 아니라 다음 세션이 할 일.

## Last updated
2026-06-02 — **실기 검증 2문제 해결 + 브랜치 배포 variant 분기 구현**. (1) host application Python 누락 → host 단독 실행 구성, (2) openwakeword 가 Python 3.12 미동작(`.tflite`→tflite-runtime, 3.12 wheel 없음). 해결: pymodbus 2.x→3.x 이관(onrobot.py ×3, read/write `isError()` 가드), openwakeword → **ai-edge-litert + `tflite_runtime→ai_edge_litert` shim**(`.tflite`/코드 유지, **컨테이너 빌드+`Model(.tflite)` 로드 실측 PASS**). 브랜치 분기: `feat/application-shell`=full host venv(`resources/host-python-deps.sh` 신설, HOST_PKGS 7개, step 12→13), `feat/application-containers`=thin client(robot_control 용 numpy/scipy/pymodbus 만 apt). **ADR-014** 신설. 양 브랜치 각 4 논리 커밋 origin push. shellcheck 0 / 시크릿 0.
> 이전(2026-05-30): 브랜치 재구성(main=설치 스크립트 전용), Phase 4 컨테이너 빌드게이트(ADR-009).

---

## Next Actions (priority order)

1. **실기(noble/Python 3.12) e2e 검증 — 양 브랜치 공통.** 이 dev 머신은 jammy/3.10 이라 불가, 실기 필수.
   - `bash install.sh` 전체 `[n/13]`(shell) / `[n/12]`(containers) 실행, reboot 포함, `--status`/`--reset` 중단-재개.
   - `ros2 run robot_control robot_control` 런타임 import OK(scipy/numpy/pymodbus), shell 은 `ros2 run pick_and_place_text detection`(ultralytics) 도.
   - **(BLOCKING, 하드웨어)** 실 RG gripper open/close/move 1회씩 — pymodbus 3.x write 는 SW(`isError`)만 검증됨. **3.x minor 의 `slave=` vs `device_id=` 인자명 확인**(설치본에 따라 다름). 미검증 실로봇 운용 금지.
   - host openwakeword: shell 은 `host-python-deps.sh` 가 `Model(.tflite)` 로드까지 검증(컨테이너에선 PASS, host 미검증). containers 는 `python3-pymodbus` apt 버전(noble 3.x)이 코드와 호환되는지.
   - 실측 버전을 `docs/COMPATIBILITY.md` 의 "application-shell host Python(venv)" 표(현재 _TBD_)에 기입.
2. **Phase 4 컨테이너 통합 (step 5, containers 브랜치, host e2e 이후)** = 진짜 Phase 4 PASS:
   - GPU 런타임: `docker run --gpus all <yolo> python3 -c "import torch; assert torch.cuda.is_available()"` (nvidia-container-toolkit + driver).
   - service 왕복: host `robot_control` ↔ 컨테이너 `/get_3d_position`(od_msg/SrvDepthPosition) + `/get_keyword`(std_srvs/Trigger). network_mode:host DDS. **od_msg type hash 정합**(host·yolo 동일 빌드).
   - 카메라 USB passthrough(`/dev/bus/usb`) + 마이크 PipeWire(`${XDG_RUNTIME_DIR}/pulse`). compose 주석 placeholder 활성화.
   - publish: `docker login` + semver/SHA tag + push (ADR-007).
3. **정리(낮음)**: ROADMAP Phase 2 체크박스 reconcile. 보류 MINOR(host-python-deps 단독 재실행 시 `apt update` 네트워크 의존 주석, build-all `--help`, pip lock 파일).

---

## Current Work State

- 코드 변경 없음 (in-progress 없음). 2문제 해결 작업은 **양 브랜치 커밋+push 완료**(shell feed18b / containers 62bd3a9).
- **`.claude/memory/` 세션 메모리 + 루트 `.gitignore`(로컬 도구 ignore) 만 미커밋** — 의도적. `.gitignore` 는 이번 작업 무관(`.understand-anything/`·`.agents/`·`.claude/skills/`·`skills-lock.json`).
- 검증 잔여 이미지 `local/ros2-jazzy-voice:dev-aiedge`(로컬, 삭제 무방).

---

## Open Decisions

- **Phase 4 통합 세부** (containers step 5 진입 시): 마이크 `device_index=10` 하드코딩(MicController/get_keyword) → 동적 매핑/PipeWire. 카메라 USB passthrough 구체.

---

## Remaining Issues

- **(BLOCKING, 하드웨어) gripper 안전**: pymodbus 3.x write 의미는 import smoke 로 검증 불가 — 실 gripper 재검증 필수. `slave=`/`device_id=` minor 차이도 실기 확인.
- **Phase 4 통합 미해결 소스 이슈** (step 5, containers):
  - YOLO 가중치 `yolov8n_tools_0122.pt` 가 `object_detection/resource/` 에 **없음**(`pick_and_place_text/resource/` 에만, 6MB). 런타임 `YoloModel()` FileNotFoundError. mount/복사 필요.
  - `object_detection` 이 `realsense2_camera` 노드 직접 안 띄움(`/camera/camera/*` subscribe 만) → 카메라 노드 별도 기동.
- **pick_and_place_voice 구조 smell**: setup.py 가 robot_control/voice_processing/object_detection 를 vendored sub-package 로 포함(`onrobot.py`·`wakeup_word.py` 중복본 존재). 동작은 하나 향후 한쪽만 패치하는 실수 경로. 리팩토링 후보(미요청).
- **.gitignore 병합 함정**: main 의 `.gitignore` 가 `.claude/ tasks/ docs/ containers/` ignore → main→dev merge 시 dev 에서 그 폴더 신규 파일 silent 추적 누락. merge 시 `.gitignore` 충돌을 dev 쪽 유지, 역방향은 cherry-pick.
- ROADMAP Phase 2 체크박스 미반영(활성 버그 아님).

---

## Context Notes (다음 세션 전제)

### 브랜치 배포 variant (ADR-014, 2026-06-02)
- 공통 코드 fix(pymodbus onrobot.py ×3, openwakeword voice Dockerfile/build-all.sh)는 **양 브랜치 동일**. host Python 설치만 갈림:
  - `feat/application-shell` = **full host monolith**: `host-python-deps.sh` 가 venv(`${DSR_WORKSPACE}/.venv`, `--system-site-packages`)에 torch cu128/ultralytics/openwakeword/langchain/pymodbus 등 설치(컨테이너 핀 미러링). `HOST_PKGS` 7개 전체. colcon 을 venv active 에서 빌드 → entry_point shebang=venv python → `ros2 run` 이 venv 봄. step 12→13(`a02_host_python_deps`). `activate.sh` 가 ROS+overlay+venv opt-in.
  - `feat/application-containers` = **thin client**: `HOST_PKGS=(robot_control od_msg)`, host 는 `python3-numpy/scipy/pymodbus` 만 apt(`dsr-project-install.sh` step 4b). yolo/voice 는 컨테이너. step 12 유지.
- 두 변종은 같은 내용에서 출발한 별도 브랜치(merge 안 함, 공통 fix 는 cherry-pick/checkout 동기화).

### openwakeword Python 3.12 레시피 (검증됨)
- 진짜 블로커 = `.tflite` 가 요구하는 **tflite-runtime**(3.12 wheel 없음, 최대 3.11), openwakeword 자체 아님. 리서치가 "0.6.0 이 ai-edge-litert 조건부 설치"라 했으나 **실제 0.6.0 은 tflite-runtime 하드 의존** — 컨테이너 빌드로 직접 확인(lessons.md L-009).
- 해법: `pip install --no-deps openwakeword==0.6.0` + 실제 의존 명시(onnxruntime/tqdm/scikit-learn/requests) + `ai-edge-litert`(cp312, 동일 Interpreter API) + `tflite_runtime→ai_edge_litert` shim 을 site-packages 에 생성 + `download_models(['__feature_only__'])`(feature 모델 wheel 미동봉). `.tflite`/`wakeup_word.py` 무변경. 검증 = `import` 아닌 `Model(.tflite)` 인스턴스화+predict.

### git 운영 / 브랜치 토폴로지
- `main`(설치 스크립트 전용) / `feat/application-shell`(full host dev, 현 작업) / `feat/application-containers`(thin client + 컨테이너). 셋 다 origin.
- `origin` = `git@github.com:Seooooooogi/ros2_jazzy_test.git`(private). 커밋: 사용자 명의만, AI attribution 금지. 메시지 외부 친화(내부 축약어 미사용).
- push 전 시크릿 스캔 필수. (주의: pre-push 스킬 스캐너 `scan_secrets.pl` 가 `.claude/skills/` 미존재 시 수동 grep 폴백.)

### 검증 함정 (lessons.md)
- **L-004** 정적 통과 ≠ 동작 / **L-007** ROS2 인터페이스 import 검증 / **L-008** Dockerfile `set -u`+ROS setup.bash / **L-009** 외부 리서치 ≠ 사실(openwakeword 의존, 빌드로 실증) + import smoke ≠ 런타임 로드.

### 도메인 사실 (유효)
- doosan-robot2: host↔controller = TCP 12345 via DRFL. gripper = OnRobot RG2/RG6, Modbus TCP(`onrobot.py`, slave=65).
- 호스트(실기) = RTX 4060 Laptop, noble/Python 3.12. 이 dev 머신 = jammy/3.10(타깃 아님).
- Voice 입력 = 노트북 내장 마이크(PipeWire). librealsense2 = Intel noble apt 정식.

---

## Current Focus
- **Top priority**: 실기(noble/3.12) e2e 검증 — `bash install.sh` + `ros2 run` + **gripper 하드웨어(BLOCKING)**. 작업 브랜치 = `feat/application-shell`.
- **Friction**: 이 dev 머신은 jammy/3.10 이라 host 런타임·GPU·gripper 검증 불가. openwakeword 레시피만 컨테이너(3.12)로 실증 완료.
