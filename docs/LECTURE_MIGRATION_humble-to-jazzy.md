# 강의안(Humble/22.04) → 현재 구현(Jazzy/24.04) 비교 · 수정 가이드

> 대상: `cobot2_notion` 크롤링 = **7기 협동로봇2 강의안(Humble 기준)**. 본 문서 = 그 강의안을 현재 레포 구현(`install.sh` + `setup-app.sh` + 컨테이너)에 맞추려면 **어디를 고쳐야 하는지** before/after 정리. 기술 상세보다 **조치 위주**.

---

## 0. 한눈에 — 축별 Before → After

| 축 | Before (강의안) | After (현재 구현) | 조치 |
|---|---|---|---|
| **OS / ROS** | Ubuntu 22.04 + ROS2 **Humble** | Ubuntu 24.04(noble) + ROS2 **Jazzy** | 전 페이지 distro 문자열 교체 |
| **설치 방식** | `Installfile_2026_{A,B}.zip` 의 `a0X`/`b0X` 개별 bash | `bash install.sh`(base 10 step) → `bash setup-app.sh`(app) | 설치 섹션 전면 교체 |
| **설치 재개** | 없음(스크립트 순서 수동) | **resumable** — 끊긴 step 부터 자동 재개, `[n/10]` 진행률 | 신규 서술 |
| **Python 책임** | 앱 라이브러리(torch/langchain/openai)를 **host 설치** | yolo 앱 Python 은 **컨테이너 안**, voice 앱 Python 은 **host 설치**(마이크 하드웨어 종속, ADR-027), robot_control 은 system Python+colcon | yolo=컨테이너 / voice=host pip 로 분리 서술 |
| **실행 모델** | pick_and_place 3-패키지를 **host 노드**로 직접 | `object_detection` = **Docker 컨테이너**, `voice_processing`·`robot_control` = **host**(voice 는 ADR-027 로 host 환원) | 실행 섹션 재작성 |
| **CUDA** | `/usr/local/cuda-12.4` host PATH | **12.8**, yolo **컨테이너 안**에만(host 미설치) | bashrc CUDA 줄 삭제 |
| **OPENAI key** | `corecode/VoiceProcessing/.env` | 사용자가 `~/.config/cobot2/.env` 직접 생성 → host voice 노드가 로드(ADR-028) | 위치 갱신·인스톨러 자동생성 없음 |
| **ROS_DOMAIN_ID** | `99` 하드코딩(화이트보드 조번호) | `setup-app` 이 prompt(기본 **42**), XDG 파일 영속 | 하드코딩 서술 삭제 |
| **`.bashrc`** | 수동 편집(source/PATH/alias) | dds-tuning 이 관리 블록 자동 주입 | 수동 편집 절차 삭제 |
| **Docker** | 별도 "이론" 섹션(외부 링크) | **런타임 그 자체**(빌드/compose/bringup) | 이론→실습 워크플로로 승격 |

---

## 1. 개발 환경 구축 (강의안 §1~2)

**Before**
- 2경로: A(Ubuntu 초기화 MSI) / B(협동1 환경 유지) 중 택1.
- `Installfile_2026_A_v2.zip` → `a01-prerequirements`(nvidia+재부팅+MOK) → `a02-about-project` → `a03-vs-code-install` → `a04-realsense01`(system) → `a05-realsense02`(ROS ws) → `a06-Voice`.
- B경로: `b01`~`b04`(realsense + Voice).
- **`.bashrc` 수동 편집**: `source /opt/ros/humble`, cuda-12.4 PATH, `dsr_common2/imp` PYTHONPATH, `ROS_DOMAIN_ID=99`, alias(`realsense`/`roboton`).

**After**
- 단일 진입: `bash install.sh`(base 10 step, confirm 1회 후 자동, step 6 자동 reboot 후 GUI autostart 재개) → `bash setup-app.sh`(workspace + yolo 컨테이너 + host voice Python).
- base = kernel/NVIDIA/Docker/**ROS2 Jazzy**/reboot/VS Code/DDS 튜닝/정적 IP/corecode 확인.
- app = `obtain_cobot2` → DSR 드라이버 → RealSense(sdk/ros) → colcon → 컨테이너 toolkit/빌드 → host voice Python 설치(`voice-host-install.sh`). OPENAI 키는 사용자가 `~/.config/cobot2/.env` 직접 생성(ADR-028).
- `.bashrc` **수동 편집 불필요** — dds-tuning 이 관리 블록 주입, 도메인은 파일에서 동적 로드.

**조치**
- **§1 설치 2경로 + `a0X`/`b0X` 절차 → `install.sh`/`setup-app.sh` 2단계로 전면 교체.**
- **§2-A `.bashrc` 수동 편집 절차 삭제** (source/CUDA/PYTHONPATH/alias/도메인 전부 자동화됨).
- MOK/nvidia-smi 확인은 유지(개념 동일), 다만 install.sh 흐름 안으로 편입.

---

## 2. Core Code · Gripper (강의안 §3)

**Before**
- `corecode.zip` → `~/corecode` 수동 배치. `modbus.ipynb` 로 RG2 그리퍼 동작 확인.

**After**
- `corecode` 는 **레포 미포함** — 사용자가 corecode.zip 을 `~` 에 풀어 `~/corecode` 배치, install.sh step 10 이 확인(ADR-029). 그리퍼는 `pymodbus` 로 제어하되 **`pymodbus<3.7` 핀 필수**(3.7+ 는 `ModbusTcpClient` 가 serial kwargs 거부 → `onrobot.py` init 실패).

**조치**
- **corecode 는 레포 미포함 — corecode.zip 별도 수령 후 `~/corecode` 배치(ADR-029)**.
- 그리퍼: modbus 개념 유지 + **pymodbus 버전 핀 주의 문구 추가**.

---

## 3. Voice Processing (강의안 §6)

**Before**
- host 에서 `python3 mic_test.py` / `wakeup_word.py` / `STT.py` / `keyword_extraction.py` 직접 실행.
- OPENAI key = `corecode/VoiceProcessing/.env`.
- keyword 추출 = GPT-4o + LangChain **LLMChain**.

**After**
- voice 는 **host 직접 실행**(ADR-027) — `ros2 run voice_processing get_keyword`(host). 마이크 하드웨어 종속(ALSA `/dev/snd` + PortAudio)이라 컨테이너 계획 철회. STT 트리거는 `ros2 service call /get_keyword std_srvs/srv/Trigger "{}"`.
- OPENAI key = 사용자가 **`~/.config/cobot2/.env`** 직접 생성(인스톨러 자동생성 없음, ADR-028), `bringup.sh` 가 host voice 노드에 로드.
- LangChain **1.0** 반영 — `PromptTemplate` import 는 `langchain_core.prompts`(구 `langchain.prompts` 제거됨).

**조치**
- **host `python3 *.py` 직접 실행은 유지(ADR-027 로 컨테이너화 철회) + 통합 노드는 host `ros2 run` + service call.**
- **.env 위치(corecode → `~/.config/cobot2/.env`) 갱신 + 인스톨러 자동생성 없음(ADR-028).**
- LangChain import 경로 갱신 문구.

---

## 4. pick and place 패키지 · 실행 (강의안 §7, §10)

**Before**
- `~/cobot_ws/src` 에 `pick_and_place_text` / `pick_and_place_voice`(1패키지) / 3패키지 분리(`object_detection`/`robot_control`/`voice_processing`).
- 실행 = host 에서 각 노드 직접 + 로봇 bringup `dsr_bringup2_rviz.launch.py mode:=real host:=192.168.1.100 ... model:=m0609`.

**After**
- cobot2 는 **레포 외부 소스** → `~/cobot_ws/src/cobot2` 에 배치(추적 제외).
- `object_detection` = **컨테이너**, `voice_processing`·`robot_control` = **host**(voice 는 ADR-027 로 host).
- 통합 실행 = **`bash containers/bringup.sh`**(로봇+카메라+컨테이너+노드 자동 기동, Ctrl+C teardown). `mode:=real`/`mode:=virtual`(에뮬레이터).
- 컨테이너는 소스 live-mount + `--symlink-install` → `.py` 수정 후 노드 재실행이면 반영(재빌드 불요).

**조치**
- **패키지를 host 노드로 나열하던 실행 절차 → 컨테이너 + `bringup.sh` 로 재작성.**
- **cobot2 배치 위치/취득 방식 명시**(레포에 없음).
- 로봇 bringup 진입점: `dsr_bringup2_rviz…` → `cobot2_bringup`(bringup.sh 내부)로 갱신.

---

## 5. Docker & Container (강의안 §9)

**Before**
- "이론" 섹션 1개 + 외부 링크. 실제 워크플로 없음(전부 host 실행).

**After**
- Docker 가 **yolo/voice 런타임의 핵심**. 학습해야 할 실습:
  - multi-stage 빌드 + `:dev-builder` 태그(builder 스테이지) — `bash containers/build-all.sh`.
  - `docker compose` base + dev override 머지, profiles, 볼륨(bind vs named).
  - `--symlink-install` 로 재빌드 없이 반영, ENTRYPOINT vs `docker exec` 환경, `network_mode: host` + DDS discovery(도메인·RMW·cyclonedds 일치).

**조치**
- **§9 를 이론 링크 → 실제 컨테이너 워크플로 실습 섹션으로 승격**(빌드/compose/bringup/재기동).
- (참고: 사내 Docker 기초 노트 별도 존재 — 개념 보강용.)

---

## 6. RealSense (강의안 §4~5)

**Before / After 대체로 유지**
- launch 명령(`rs_align_depth_launch.py … align_depth.enable:=true …`)·IR 사용법 거의 동일.
- realsense-ros = **realsenseai** org(구 intel). 강의안이 이미 realsenseai 반영 → OK.

**조치**
- **거의 유지.** 다만 SDK 설치는 `a04`/`b02` 스크립트 → `setup-app.sh` RealSense 단계로 경로만 교체. apt repo/키가 realsenseai 신 도메인·2025-11 신 키인지 확인(현재 구현 반영됨).

---

## 7. 그대로 유지해도 되는 것

- **Camera Calibration 개념·verify 흐름**(§4) — 좌표 추출/pick&place 로직 학습 가치 동일.
- **Object Detection 이론**(§8 모델 분류/AABB/OBB/Segmentation…) — distro 무관.
- **Doosan Topic/Service 리스트**(§12), **매뉴얼·아키텍처 링크**(§13) — Jazzy 문서 링크 이미 사용 중.
- **rokey utility(get_cur_pos/jog)**(§11), **로봇 물리 연결/ping/IP 확인**(§2-C~E) — 개념 유지(정적 IP 는 install.sh network step 이 설정).

---

## 8. 새 강의안에 꼭 신설할 섹션

1. **설치 = `install.sh` → `setup-app.sh` 2단계** (resumable, 진행률, reboot 자동 재개).
2. **컨테이너 워크플로** (빌드 → `bringup.sh` → `docker exec` → `ros2 run`, 소스 수정 반영 규칙).
3. **cobot2 소스 취득/배치** (`~/cobot_ws/src/cobot2`, 레포 외부).
4. **OPENAI key = 사용자가 `~/.config/cobot2/.env` 직접 생성** (인스톨러 자동생성 없음, host voice 노드가 로드 — ADR-028).
5. **ROS_DOMAIN_ID prompt(기본 42)** — 조별 하드코딩 폐기.

---

## 9. 스크린샷 검토 — 실물로 확인·정정된 것

강의안 크롤링의 스크린샷 55장 전수 검토(클러스터별). 마이그레이션에 의미 있는 확정 사항:

- **Python 버전**: 강의안 `3.10.12`(Ubuntu 22.04) → 현재 `3.12`(24.04). keyword_extraction 실행 스샷의 상태바로 확정.
- **numpy 충돌 실물**: `a06/b04-Voice` 설치 출력에 `opencv-python 4.13.0.90 requires numpy>=2 ... but you have numpy 1.24.4 which is incompatible` 경고 그대로 노출. **host 레벨 충돌** → 현재는 컨테이너 안 `numpy<2` 핀으로 격리. (강의안은 "numpy 1.24.4 뜨면 정상"이라 넘어가지만, 근본은 pin 문제.)
- **langchain import 실물**: `keyword_extraction.py` 가 `from langchain.prompts import PromptTemplate` + `ChatOpenAI(model="gpt-4o", temperature=0.5)`. 구 import 는 langchain 1.0 에서 제거 → 현재 repo 는 `langchain_core.prompts` 로 이미 교체(반영됨). **강의안 코드 스샷도 갱신 필요.** (§6-D 본문의 "LLMChain" 표현도 실제 코드는 `ChatOpenAI` 직접 → 문구 정정.)
- **corecode 실제 4개 디렉토리**: `Calibration_Tutorial` / `DRL_Tutorial` / `OD_Tutorial` / `VoiceProcessing`. 본문(§3)은 2개만 언급 → **본문 보강**. (현재 repo corecode 도 동일 4개 — 구조 일치.)
- **VoiceProcessing 구성**: `keyword_extraction.py`·`MicController.py`·`mic_test.py`·`STT.py`·`wakeup_word.py`·`.env`·`class_embeddings.json`·`hello_rokey_8332_32.tflite`. tflite wakeword 모델명이 현재 host voice smoke 검증과 동일.
- **workspace 구조**: 강의안 `~/cobot_ws/src/{cobot1_ws, cobot2_ws, doosan-robot2}`, cobot2_ws = 7패키지(object_detection·od_msg·pick_and_place_text·pick_and_place_voice·robot_control·rokey·voice_processing). 현재 = `~/cobot_ws/src/cobot2`(+ doosan-robot2 드라이버). **cobot2_ws → cobot2 로 이름/구조 재편 + 컨테이너화 분담** 안내 필요.
- **그리퍼 실물**: `from onrobot import RG`, RG2, `192.168.1.1:502`, pymodbus — 현재 `pymodbus<3.7` 핀(3.7+ 는 `ModbusTcpClient` 잉여 kwargs 거부). 핀 주의 유효.
- **로봇 API 불변**: topic `/dsr01/*`, service `/dsr01/aux_control|controller_manager/*`, `robot_model=m0609`, `dsr01` prefix — Humble/Jazzy 공통(doosan-robot2 드라이버). rokey `get_current_pos` 의 tk 좌표 복사 UI 도 그대로 유효.
- **이론/기초는 그대로**: object detection 개념(AABB/bbox), YOLO COCO 데모, ROS pub/sub 튜토리얼(`simple_publisher/subscriber.py`), calibration `calibrate_data.json`(file_name/pos/type) — distro 무관, 수정 불요.

> 장식용(Unsplash 커버 2장)·아이콘(github/favicon)은 검토 제외. 나머지 미개봉 스샷은 위 클러스터의 연속 화면(추가 service list, realsense/voice/rokey GUI, 아키텍처 다이어그램)으로 판단 결과 동일 결론.

---

## 부록 — 삭제/대체 대상 요약

| 강의안 항목 | 상태 | 대체 |
|---|---|---|
| `Installfile_*.zip` + `a0X`/`b0X` | **삭제** | `install.sh` / `setup-app.sh` |
| `.bashrc` 수동 편집(source/CUDA/PYTHONPATH/alias/도메인) | **삭제** | 자동(dds-tuning 블록 + XDG 도메인 파일) |
| `a06-Voice`/`b04-Voice` host 음성 라이브러리 설치 | **대체** | host `voice-host-install.sh`(system pip, ADR-027) |
| host `python3 STT.py` 등 직접 실행 | **유지** | host 직접 실행(voice=host) + 통합 노드는 `ros2 run` + `ros2 service call` |
| CUDA 12.4 host PATH | **대체** | 12.8, yolo 컨테이너 내부 |
| `ROS_DOMAIN_ID=99` 하드코딩 | **대체** | prompt 기본 42 |
| Humble / `/opt/ros/humble` 문자열 전부 | **대체** | Jazzy / `/opt/ros/jazzy` |
