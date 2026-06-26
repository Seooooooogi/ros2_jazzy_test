# venv 기반 pick & place 교육용 데모 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 모놀리식 `pick_and_place_text` / `pick_and_place_voice` 노드를 host venv 로 직접 실행하는 line-by-line 실습 가이드를 만들어, "컨테이너 사용 유무"의 효과를 학생에게 체감시킨다.

**Architecture:** 두 패키지를 격리 colcon overlay(`~/.cobot2_venv_demo/ws`)로 빌드하고, 컨테이너 Dockerfile 핀을 미러한 단일 venv(`~/.cobot2_venv_demo/venv`, `--system-site-packages`)에 application 의존을 설치한다. 실행은 `containers/entrypoint.sh` 와 동일하게 ROS/overlay source + venv site-packages 를 `PYTHONPATH` 주입 후 `ros2 run`. 산출물은 `~/.cobot2_venv_demo/` 로 격리해 teardown 가능.

**Tech Stack:** ROS2 Jazzy (Python 3.12), colcon, `python3 -m venv` + `pip`, PyTorch cu128, ultralytics, langchain/openai, openwakeword(+ai-edge-litert shim), pyaudio/sounddevice, pymodbus, DSR(`DSR_ROBOT2`), RealSense.

**Spec:** `docs/specs/2026-06-26-venv-pickplace-demo-design.md` (승인본). 본 계획은 그 스펙을 태스크로 분해한다. 각 명령의 근거는 스펙 §번호 참조.

## Global Constraints

본 섹션 제약은 모든 태스크에 암묵 포함된다.

- **distro/python**: ROS2 `jazzy`, Python `3.12`(noble). 경로는 glob(`python*/site-packages`)로 버전 비종속 표기.
- **CUDA wheel**: PyTorch `--index-url https://download.pytorch.org/whl/cu128` (cu128 = `resources/config.sh` 의 `CUDA_VERSION` 기준).
- **numpy 핀**: `pip install --force-reinstall "numpy<2"` 는 **항상 마지막 pip 작업** + 직후 import 검증. 위반 시 transitive 상향으로 ultralytics 런타임 실패.
- **버전 상한 핀**: `ultralytics<9`, `opencv-python<4.10`, `scipy<1.18`, `langchain<2`, `langchain-openai<2`, `openai<3`, `openwakeword==0.6.0`(`--no-deps`), `onnxruntime<2,>=1.10.0`, `tqdm<5,>=4.0`, `scikit-learn<2,>=1`, `requests<3,>=2.0`, `ai-edge-litert>=2.0.2,<3`. (모놀리식 추가: `pymodbus` — 그리퍼 Modbus.)
- **외부 소스 비추적**: `~/cobot_ws/src/cobot2` 는 이 레포가 추적하지 않는다. cobot2 in-place 수정(COLCON_IGNORE 제거 / rename / 에셋 / 마이크 fix)은 **이 레포에 커밋하지 않는다**. 레포 커밋 대상은 `scripts/venv-demo/*`, `README.md`, 본 계획·스펙(`docs/`)뿐.
- **DDS 일치(R8)**: 모든 build/run 터미널 prologue 첫 줄 `set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a` (RMW=cyclonedds / ROS_DOMAIN_ID=42 / CYCLONEDDS_URI).
- **line-targeted 편집(R5/§5)**: rename 은 import 6줄 + setup.py 만. 전역 `sed s/<name>/ppv_<name>/g` 금지 — 노드명 문자열(`"robot_control_node"`, `'object_detection_node'`)·실행파일명 오염.
- **격리/teardown**: 데모 산출물은 `~/.cobot2_venv_demo/` 에만. `rm -rf ~/.cobot2_venv_demo` 로 완전 제거.
- **커밋 규약**: AI attribution(Co-Authored-By 등) 금지 — 사용자 명의. 메시지는 외부 이해 가능·기능 단위·한국어+영어 식별자, 내부 코드(Phase/ADR/Hard Rule/R번호) 미사용.
- **하드웨어 게이팅**: 실행 검증 중 카메라/마이크/그리퍼 필요분은 `[HW]` 표기 — 에뮬레이터+노드 기동(import/asset/ROS 연결)까지는 무하드웨어 검증 가능.

**검증 스타일**: 본 작업은 unit test 가 아니라 **검증 명령(verification-first)** 으로 TDD 규율을 적용한다 — "지금은 실패하는 확인 명령을 먼저 실행 → 변경 적용 → 같은 명령이 통과" 순서. 산출물(LAB.md/requirements.txt/README)은 레포에 커밋, cobot2 변경은 검증만.

---

### Task 1: 레포 스캐폴드 + requirements.txt + LAB.md 골격

**Files:**
- Create: `scripts/venv-demo/requirements.txt`
- Create: `scripts/venv-demo/LAB.md` (골격: 헤더 + 대비 intro + 사전점검(Part 0) + Part A/B/C 빈 섹션)

**Interfaces:**
- Produces: `scripts/venv-demo/` 디렉토리, 이후 태스크가 LAB.md 의 각 Part 섹션을 채운다.

- [ ] **Step 1: requirements.txt 작성** (핀 대조용 — 설치는 LAB.md 가 단계별 pip 로 수행. 본 파일은 "정답 핀" 참조본)

```text
# venv-demo 의존 핀 — containers/{yolo-detection,voice-processing}/Dockerfile 미러 + 모놀리식 추가분.
# 설치 순서/방법은 LAB.md Part A4 참조(numpy<2 는 반드시 마지막). 본 파일은 핀 대조용 reference.
# torch/torchvision 은 별도 index(cu128)라 여기 버전 미기재 — LAB.md 의 --index-url 명령 사용.
ultralytics<9
opencv-python<4.10
langchain<2
langchain-openai<2
openai<3
pyaudio
sounddevice
scipy<1.18
python-dotenv
pymodbus
openwakeword==0.6.0
onnxruntime<2,>=1.10.0
tqdm<5,>=4.0
scikit-learn<2,>=1
requests<3,>=2.0
ai-edge-litert>=2.0.2,<3
numpy<2
```

- [ ] **Step 2: LAB.md 골격 작성**

`scripts/venv-demo/LAB.md` 에 다음 골격을 작성한다(섹션 본문은 후속 태스크가 채움):

```markdown
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
(Task 1 Step 3)

## Part A — 1회 환경 구성
### A1. 원본 패키지 활성화 (COLCON_IGNORE 제거)
### A2. voice 번들 rename + 마이크 fix
### A3. venv 생성
### A4. 의존성 설치 (pip)
### A4b. voice 에셋 스테이징
### A5. colcon 빌드 (격리 overlay)

## Part B — 실행
### text 데모 (터미널 3개)
### voice 데모 (터미널 4개)

## Part C — 정리 & 대비
```

- [ ] **Step 3: Part 0 사전 점검 섹션 작성** (LAB.md `## Part 0` 아래)

```markdown
한 줄씩 실행해 전제를 확인한다(하나라도 실패하면 정식 설치 먼저).

```bash
# ROS2 jazzy 존재
ros2 --version                                   # 예상: ros2 ... (명령 인식)
# host colcon 빌드본에 DSR + od_msg (overlay 의존)
ls ~/cobot_ws/install/dsr_common2/lib/python3.12/site-packages/DSR_ROBOT2.py   # 예상: 경로 출력
ls ~/cobot_ws/install/od_msg                     # 예상: include lib share
# 두 원본 패키지 존재
ls ~/cobot_ws/src/cobot2/pick_and_place_text ~/cobot_ws/src/cobot2/pick_and_place_voice
# config.sh (RMW/도메인 소스) 존재
ls ~/ros2_jazzy_test/resources/config.sh
``` 
```

- [ ] **Step 4: 검증** — 파일 존재 + Part 0 명령이 이 머신에서 통과

Run:
```bash
test -f scripts/venv-demo/requirements.txt && test -f scripts/venv-demo/LAB.md && echo "files OK"
ros2 --version >/dev/null 2>&1 && ls ~/cobot_ws/install/od_msg >/dev/null && echo "prereq OK"
```
Expected: `files OK` 와 `prereq OK` 둘 다 출력.

- [ ] **Step 5: Commit**

```bash
git add scripts/venv-demo/requirements.txt scripts/venv-demo/LAB.md
git commit -m "venv 실습 데모 스캐폴드와 의존성 핀 목록 추가"
```

---

### Task 2: cobot2 원본 활성화 + voice 번들 rename (LAB.md A1·A2-rename)

**Files:**
- Modify (cobot2, 비추적): `~/cobot_ws/src/cobot2/pick_and_place_text/COLCON_IGNORE`(삭제), `pick_and_place_voice/COLCON_IGNORE`(삭제)
- Modify (cobot2, 비추적): `pick_and_place_voice/{robot_control,object_detection,voice_processing}` → `ppv_*` + import 6줄 + `setup.py`
- Modify (repo): `scripts/venv-demo/LAB.md` (A1, A2-rename 섹션)

**Interfaces:**
- Consumes: Task 1 의 LAB.md 골격.
- Produces: rename 된 voice 패키지 구조(`ppv_robot_control`/`ppv_object_detection`/`ppv_voice_processing`) — Task 5 colcon 빌드가 의존.

- [ ] **Step 1: 검증 명령 먼저 (현재는 충돌 상태 확인)**

Run:
```bash
ls ~/cobot_ws/src/cobot2/pick_and_place_text/COLCON_IGNORE ~/cobot_ws/src/cobot2/pick_and_place_voice/COLCON_IGNORE
grep -rl "from robot_control" ~/cobot_ws/src/cobot2/pick_and_place_voice/
```
Expected: COLCON_IGNORE 2개 존재 + `from robot_control` 잔존(아직 미수정) → 변경 전 상태 확인.

- [ ] **Step 2: LAB.md A1 섹션 작성 + 실행** (COLCON_IGNORE 제거)

LAB.md `### A1` 에 기록 후 실행:
```bash
rm ~/cobot_ws/src/cobot2/pick_and_place_text/COLCON_IGNORE
rm ~/cobot_ws/src/cobot2/pick_and_place_voice/COLCON_IGNORE
```

- [ ] **Step 3: LAB.md A2-rename 섹션 작성 + 실행** (디렉토리 mv 3개)

```bash
cd ~/cobot_ws/src/cobot2/pick_and_place_voice
mv robot_control    ppv_robot_control
mv object_detection ppv_object_detection
mv voice_processing ppv_voice_processing
```

- [ ] **Step 4: import 교정 6줄 (line-targeted, 전역 sed 금지)**

LAB.md 에 기록 후 실행 (각 파일의 해당 import 줄만):
```bash
cd ~/cobot_ws/src/cobot2/pick_and_place_voice
sed -i 's/^from robot_control\.onrobot import RG/from ppv_robot_control.onrobot import RG/' ppv_robot_control/robot_control.py
sed -i 's/^from object_detection\.realsense import ImgNode/from ppv_object_detection.realsense import ImgNode/' ppv_object_detection/detection.py
sed -i 's/^from object_detection\.yolo import YoloModel/from ppv_object_detection.yolo import YoloModel/' ppv_object_detection/detection.py
sed -i 's/^from voice_processing\.MicController import/from ppv_voice_processing.MicController import/' ppv_voice_processing/get_keyword.py
sed -i 's/^from voice_processing\.wakeup_word import WakeupWord/from ppv_voice_processing.wakeup_word import WakeupWord/' ppv_voice_processing/get_keyword.py
sed -i 's/^from voice_processing\.stt import STT/from ppv_voice_processing.stt import STT/' ppv_voice_processing/get_keyword.py
```
> 노드명 문자열(`"robot_control_node"` robot_control.py:34, `'object_detection_node'` detection.py:18)은 `^from ...` 앵커 덕에 건드리지 않는다 — 의도된 보호.

- [ ] **Step 5: setup.py 교정** (find_packages + entry_points 우측 모듈경로)

```bash
cd ~/cobot_ws/src/cobot2/pick_and_place_voice
sed -i "s/'robot_control', /'ppv_robot_control', /;s/'voice_processing', /'ppv_voice_processing', /;s/'object_detection'/'ppv_object_detection'/" setup.py
sed -i "s#robot_control\.robot_control:main#ppv_robot_control.robot_control:main#;s#object_detection\.detection:main#ppv_object_detection.detection:main#;s#voice_processing\.get_keyword:main#ppv_voice_processing.get_keyword:main#" setup.py
```

- [ ] **Step 6: 검증** — dangling import 0 + 노드명 문자열 보존 + AST 파싱 OK

Run:
```bash
cd ~/cobot_ws/src/cobot2/pick_and_place_voice
# 1) generic import 잔존 0 (ppv_ 접두 제외)
grep -rnE "^from (robot_control|object_detection|voice_processing)\." . && echo "FAIL: dangling import" || echo "imports OK"
# 2) 노드명 문자열 보존
grep -q '"robot_control_node"' ppv_robot_control/robot_control.py && grep -q "'object_detection_node'" ppv_object_detection/detection.py && echo "node-name strings OK"
# 3) 파싱 무결성
python3 -c "import ast,glob; [ast.parse(open(f).read()) for f in glob.glob('ppv_*/**/*.py',recursive=True)+['setup.py']]; print('ast OK')"
# 4) entry_points 갱신 확인
grep -E "ppv_(robot_control|object_detection|voice_processing)\.(robot_control|detection|get_keyword):main" setup.py
```
Expected: `imports OK`, `node-name strings OK`, `ast OK`, 그리고 3개 entry_point 라인 출력.

- [ ] **Step 7: Commit** (LAB.md 만 — cobot2 변경은 비추적)

```bash
git add scripts/venv-demo/LAB.md
git commit -m "실습 가이드에 원본 활성화와 voice 번들 네임스페이스 정리 단계 추가"
```

---

### Task 3: 마이크 fix (LAB.md A2-mic) — [HW] 하드웨어 게이트

> **실행 순서 주의**: device 인덱스 probe(Step 2)는 pyaudio 가 필요하므로 **Task 4(venv+deps) 이후** 수행한다. 권장 순서: T1 → T2 → T4 → **T3** → T5 → T6/T7. 정적 편집(Step 1·3·4)은 Task 2 직후라도 가능하나, **device_index 실측 치환(Step 2·3b)·런타임 검증(Step 6)은 Task 4 뒤**. 정적 편집은 import 가능한 **유효 정수 기본값(10)을 유지**해 빌드를 깨지 않는다.

**배경**: 모놀리식 voice 의 마이크 경로는 **wakeword=pyaudio(`MicController`, 48kHz, `device_index=10`, `input_device_index` 주석) + STT=sounddevice(`sd.rec`)** 이중 경로. 이 워크스테이션 DMIC 는 48kHz 장치(hw:1,6)가 정적에서도 클리핑 노이즈 → wakeword confidence≈0.001. 깨끗한 장치 = hw:1,7(16kHz 네이티브). 컨테이너는 sounddevice 일원화로 `resolve_input_device()` 를 썼으나 모놀리식은 pyaudio 라 **그대로 드롭인 불가** — pyaudio device index probe + rate 16k 전환 필요.

**Files:**
- Create (cobot2, 비추적): `~/cobot_ws/src/cobot2/pick_and_place_voice/ppv_voice_processing/audio_device.py` (donor 복사)
- Modify (cobot2, 비추적): `ppv_voice_processing/MicController.py`(device_index/rate), `ppv_voice_processing/stt.py`(sd.rec device=)
- Modify (repo): `scripts/venv-demo/LAB.md` (A2-mic 섹션)

**Interfaces:**
- Consumes: Task 2 의 rename(`ppv_voice_processing`).
- Produces: 깨끗한 16kHz 입력으로 캡처하는 voice 노드 — Task 7 voice 실행이 의존.

- [ ] **Step 1: donor audio_device.py 복사 (LAB.md 기록 + 실행)**

```bash
cp ~/cobot_ws/src/cobot2/voice_container/voice_processing/voice_processing/audio_device.py \
   ~/cobot_ws/src/cobot2/pick_and_place_voice/ppv_voice_processing/audio_device.py
```
(donor 의 `resolve_input_device()`: `VOICE_MIC_DEVICE` env → 16kHz 네이티브 자동선택 → None. sounddevice 인덱스 기준.)

- [ ] **Step 2: [HW] pyaudio 장치 인덱스 probe** — MicController 는 pyaudio 라 sounddevice 인덱스와 다름. 실측으로 16kHz 네이티브(hw:1,7) 의 pyaudio 인덱스를 찾는다.

Run (마이크 연결 상태에서):
```bash
source ~/.cobot2_venv_demo/venv/bin/activate   # pyaudio 설치 후(Task 4) 실행
python3 -c "import pyaudio; p=pyaudio.PyAudio(); [print(i, p.get_device_info_by_index(i)['name'], int(p.get_device_info_by_index(i)['defaultSampleRate']), p.get_device_info_by_index(i)['maxInputChannels']) for i in range(p.get_device_count())]"
```
Expected: 장치 목록 출력. `hw:1,7`/16000Hz/입력채널>0 에 해당하는 **인덱스 N** 을 기록. (Task 4 이후에 수행 — pyaudio 필요.)

- [ ] **Step 3: MicController.py 정적 교정 (LAB.md 기록)** — 16kHz 네이티브 + 장치 인덱스 활성화 (기본값은 유효 정수 유지)

`ppv_voice_processing/MicController.py` 의 `MicConfig` 와 `open_stream()`:
- `rate: int = 48000` → `rate: int = 16000`
- `open_stream()` 의 주석 `# input_device_index=self.config.device_index` → 주석 해제 (`device_index` 기본 `10` 은 그대로 둬 import 안전 — 실측 인덱스는 Step 3b 에서 치환)

```bash
cd ~/cobot_ws/src/cobot2/pick_and_place_voice/ppv_voice_processing
sed -i 's/^    rate: int = 48000/    rate: int = 16000/' MicController.py
sed -i 's/^            # input_device_index=self.config.device_index/            input_device_index=self.config.device_index,/' MicController.py
```
> wakeup_word.py 의 `scipy.signal.resample` 은 16k→16k 면 사실상 no-op 이라 그대로 둔다. `device_index` 는 아직 `10`(유효 정수) — 모듈 import·빌드는 깨지지 않으나 실제 캡처 장치는 Step 3b 치환 후 정확해진다.

- [ ] **Step 3b: [HW] device_index 실측 치환** (Task 4 이후, Step 2 probe 결과 N 사용)

```bash
cd ~/cobot_ws/src/cobot2/pick_and_place_voice/ppv_voice_processing
sed -i 's/^    device_index: int = 10/    device_index: int = N/' MicController.py   # N=Step 2 의 hw:1,7 pyaudio 인덱스(정수)
```
치환 후 `grep -n 'device_index: int' MicController.py` 로 정수인지 육안 확인.

- [ ] **Step 4: stt.py 교정 (LAB.md 기록)** — STT 녹음도 깨끗한 장치로

`ppv_voice_processing/stt.py`: 상단에 `from ppv_voice_processing.audio_device import resolve_input_device` 추가, `sd.rec(...)` 에 `device=resolve_input_device()` 인자 추가.
```bash
cd ~/cobot_ws/src/cobot2/pick_and_place_voice/ppv_voice_processing
sed -i '/^import scipy.io.wavfile as wav/a from ppv_voice_processing.audio_device import resolve_input_device' stt.py
sed -i 's/sd\.rec(int(self\.duration \* self\.samplerate), samplerate=self\.samplerate, channels=1, dtype=.int16.)/sd.rec(int(self.duration * self.samplerate), samplerate=self.samplerate, channels=1, dtype="int16", device=resolve_input_device())/' stt.py
```

- [ ] **Step 5: 검증 (정적) — AST 파싱 + import 경로**

Run:
```bash
cd ~/cobot_ws/src/cobot2/pick_and_place_voice/ppv_voice_processing
python3 -c "import ast; [ast.parse(open(f).read()) for f in ['audio_device.py','MicController.py','stt.py']]; print('ast OK')"
grep -q "from ppv_voice_processing.audio_device import resolve_input_device" stt.py && echo "stt import OK"
grep -q "input_device_index=self.config.device_index," MicController.py && echo "mic device OK"
```
Expected: `ast OK`, `stt import OK`, `mic device OK`. (단 `device_index: int = N` 의 N 이 실측 정수로 치환됐는지 육안 확인.)

- [ ] **Step 6: [HW] 검증 (런타임) — wakeword 탐지** (Task 5 빌드 후 수행)

voice 노드 기동 상태에서 "Hello Rokey" 발화 → 로그 `confidence > 0.3` + "Wakeword detected". (Task 7 의 voice 실행 절차로 검증.) 마이크 없으면 이 단계 deferred.

- [ ] **Step 7: Commit** (LAB.md 만)

```bash
git add scripts/venv-demo/LAB.md
git commit -m "실습 가이드에 모놀리식 voice 마이크 입력장치 선택 단계 추가"
```

---

### Task 4: venv 생성 + 의존성 설치 + 에셋 스테이징 (LAB.md A3·A4·A4b)

**Files:**
- Create (격리, 비추적): `~/.cobot2_venv_demo/venv`
- Modify (cobot2, 비추적): `pick_and_place_voice/resource/` 에 `.pt`/`.npy` 복사
- Modify (repo): `scripts/venv-demo/LAB.md` (A3, A4, A4b)

**Interfaces:**
- Consumes: Task 2 rename(빌드 전이라 직접 의존은 아니나 동일 머신 상태).
- Produces: import 검증 통과한 venv + voice 에셋 — Task 5 빌드 / Task 6·7 실행이 의존.

- [ ] **Step 1: LAB.md A3 작성 + 실행** (시스템 deps + venv)

```bash
# (0) pyaudio 컴파일용. libsndfile1 은 컨테이너 미러(필수 아님).
sudo apt install -y portaudio19-dev libsndfile1
# (1) venv (--system-site-packages 로 rclpy/cv_bridge 등 ROS python 공유)
python3 -m venv --system-site-packages ~/.cobot2_venv_demo/venv
source ~/.cobot2_venv_demo/venv/bin/activate
pip install --upgrade pip
```

- [ ] **Step 2: LAB.md A4 작성 + 실행** (pip 레시피 — 스펙 §6 순서대로)

```bash
# (2) torch 최우선 (cu128, 수 GB)
pip install --index-url https://download.pytorch.org/whl/cu128 torch torchvision
pip install "ultralytics<9"
pip install "opencv-python<4.10"
# (3) LLM/음성
pip install "langchain<2" "langchain-openai<2" "openai<3" pyaudio sounddevice "scipy<1.18" python-dotenv
# (4) 그리퍼 Modbus (모놀리식 추가분)
pip install pymodbus
# (5) openwakeword — Python 3.12 우회
pip install --no-deps "openwakeword==0.6.0"
pip install "onnxruntime<2,>=1.10.0" "tqdm<5,>=4.0" "scikit-learn<2,>=1" "requests<3,>=2.0" "ai-edge-litert>=2.0.2,<3"
python3 -c "import os,ai_edge_litert as a; d=os.path.join(os.path.dirname(os.path.dirname(a.__file__)),'tflite_runtime'); os.makedirs(d,exist_ok=True); open(os.path.join(d,'__init__.py'),'w').close(); open(os.path.join(d,'interpreter.py'),'w').write('from ai_edge_litert.interpreter import Interpreter  # noqa: F401\n')"
OWW_DIR="$(python3 -c 'import os,openwakeword;print(os.path.join(os.path.dirname(openwakeword.__file__),"resources","models"))')"
mkdir -p "$OWW_DIR" && cp ~/ros2_jazzy_test/containers/voice-processing/oww_models/* "$OWW_DIR"/
python3 -c "import os; d='$OWW_DIR'; [ (open(os.path.join(d,f),'rb').read(8)[4:8]==b'TFL3') or (_ for _ in ()).throw(SystemExit('corrupt tflite: '+f)) for f in os.listdir(d) if f.endswith('.tflite')]; print('feature models TFL3 OK')"
# (6) numpy<2 마지막 재핀 + 검증
pip install --force-reinstall "numpy<2"
```

- [ ] **Step 3: LAB.md A4b 작성 + 실행** (voice 에셋 스테이징 — R7)

```bash
cp ~/cobot_ws/src/cobot2/pick_and_place_text/resource/yolov8n_tools_0122.pt ~/cobot_ws/src/cobot2/pick_and_place_voice/resource/
cp ~/cobot_ws/src/cobot2/pick_and_place_text/resource/T_gripper2camera.npy  ~/cobot_ws/src/cobot2/pick_and_place_voice/resource/
```

- [ ] **Step 4: 검증 — import 일괄 + numpy<2 + 에셋 존재**

Run:
```bash
source ~/.cobot2_venv_demo/venv/bin/activate
python3 -c "import numpy,torch,ultralytics,cv2,langchain,langchain_openai,openai,pyaudio,sounddevice,scipy,openwakeword,ai_edge_litert,tflite_runtime.interpreter,pymodbus; assert numpy.__version__.startswith('1.'), numpy.__version__; print('deps OK', numpy.__version__)"
ls ~/cobot_ws/src/cobot2/pick_and_place_voice/resource/yolov8n_tools_0122.pt ~/cobot_ws/src/cobot2/pick_and_place_voice/resource/T_gripper2camera.npy
```
Expected: `deps OK 1.x.y` + 두 에셋 경로 출력.

- [ ] **Step 5: Commit** (LAB.md 만)

```bash
git add scripts/venv-demo/LAB.md
git commit -m "실습 가이드에 venv 생성과 의존성 설치, 에셋 준비 단계 추가"
```

---

### Task 5: 격리 overlay colcon 빌드 (LAB.md A5)

**Files:**
- Create (격리, 비추적): `~/.cobot2_venv_demo/ws/{src,build,install}`
- Modify (repo): `scripts/venv-demo/LAB.md` (A5)

**Interfaces:**
- Consumes: Task 2(rename), Task 4(venv·에셋).
- Produces: `~/.cobot2_venv_demo/ws/install` overlay (두 패키지 + share/resource) — Task 6·7 실행이 source.

- [ ] **Step 1: LAB.md A5 작성 + 실행** (빌드는 system python — venv deactivate 선행)

```bash
deactivate 2>/dev/null || true
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
mkdir -p ~/.cobot2_venv_demo/ws/src
ln -sfn ~/cobot_ws/src/cobot2/pick_and_place_text  ~/.cobot2_venv_demo/ws/src/pick_and_place_text
ln -sfn ~/cobot_ws/src/cobot2/pick_and_place_voice ~/.cobot2_venv_demo/ws/src/pick_and_place_voice
cd ~/.cobot2_venv_demo/ws && colcon build
```

- [ ] **Step 2: 검증 — 빌드 성공 + 두 패키지 + 리소스 설치 + share 해소**

Run:
```bash
source ~/.cobot2_venv_demo/ws/install/setup.bash
ros2 pkg list | grep -E "pick_and_place_(text|voice)"
ls ~/.cobot2_venv_demo/ws/install/pick_and_place_voice/share/pick_and_place_voice/resource/yolov8n_tools_0122.pt
python3 -c "from ament_index_python.packages import get_package_share_directory as g; print(g('pick_and_place_text')); print(g('pick_and_place_voice'))"
```
Expected: 두 패키지명 출력 + `.pt` share 경로 존재 + 두 share 경로 출력(에러 없음).

- [ ] **Step 3: Commit** (LAB.md 만)

```bash
git add scripts/venv-demo/LAB.md
git commit -m "실습 가이드에 격리 워크스페이스 colcon 빌드 단계 추가"
```

---

### Task 6: text 데모 실행 (LAB.md Part B — text)

**Files:**
- Modify (repo): `scripts/venv-demo/LAB.md` (Part B text, 터미널 3개)

**Interfaces:**
- Consumes: Task 5 overlay, Task 4 venv.
- Produces: 검증된 text 실행 절차.

- [ ] **Step 1: LAB.md Part B text 작성** (터미널 3개 literal — 스펙 §8)

각 터미널 prologue 첫 줄 `set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a`:
```bash
# ── 터미널 1: 드라이버 + 카메라 (host, 에뮬레이터) ──
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
ros2 launch cobot2_bringup bringup_all.launch.py mode:=virtual
#  실로봇: ... mode:=real host:=192.168.1.100

# ── 터미널 2: YOLO depth 서비스 노드 (venv) ──
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
source ~/.cobot2_venv_demo/ws/install/setup.bash
export PYTHONPATH="$(ls -d ~/.cobot2_venv_demo/venv/lib/python*/site-packages):$PYTHONPATH"
ros2 run pick_and_place_text detection

# ── 터미널 3: 오케스트레이터 (venv) ──
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
source ~/.cobot2_venv_demo/ws/install/setup.bash
export PYTHONPATH="$(ls -d ~/.cobot2_venv_demo/venv/lib/python*/site-packages):$PYTHONPATH"
ros2 run pick_and_place_text robot_move
```

- [ ] **Step 2: 검증 (무HW 부분) — detection 노드 import/asset 무결 기동**

터미널 1(bringup virtual) 가동 상태에서 터미널 2 절차 실행. Expected: `ros2 run pick_and_place_text detection` 가 `ModuleNotFoundError`/`FileNotFoundError` 없이 기동(YOLO 가중치 로드 로그). 카메라 토픽 미수신 경고는 허용([HW]).

Run (보조 확인):
```bash
ros2 node list | grep -i detection      # 예상: detection 노드 등장
```

- [ ] **Step 3: [HW] 검증 — robot_move + 에뮬 모션**

터미널 3 `robot_move` 기동 → `/get_depth_position`(또는 해당) 서비스 호출 → 가상 로봇 모션. 그리퍼 Modbus(192.168.1.1)는 실하드웨어 없으면 해당 동작만 실패(R1) — 노드 자체 기동은 확인.

- [ ] **Step 4: Commit** (LAB.md)

```bash
git add scripts/venv-demo/LAB.md
git commit -m "실습 가이드에 text 데모 실행 절차 추가"
```

---

### Task 7: voice 데모 실행 (LAB.md Part B — voice) — [HW]

**Files:**
- Modify (repo): `scripts/venv-demo/LAB.md` (Part B voice, 터미널 4개)

**Interfaces:**
- Consumes: Task 3(마이크), Task 5 overlay, Task 4 venv.
- Produces: 검증된 voice 실행 절차.

- [ ] **Step 1: LAB.md Part B voice 작성** (터미널 4개 — 스펙 §8)

터미널 1(bringup, text 와 동일) / 2(`object_detection`) / 3(`get_keyword`, **여기서 OPENAI 키**) / 4(`robot_control`). venv 노드 prologue = config.sh + ros + cobot_ws + 데모 overlay + PYTHONPATH.
```bash
# ── 터미널 3: get_keyword (venv) — OpenAI 실제 소비처 ──
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
source ~/.cobot2_venv_demo/ws/install/setup.bash
export PYTHONPATH="$(ls -d ~/.cobot2_venv_demo/venv/lib/python*/site-packages):$PYTHONPATH"
export OPENAI_API_KEY=sk-...                      # robot_control 아님 — get_keyword 가 ChatOpenAI/STT 사용
ros2 run pick_and_place_voice get_keyword
# ── 터미널 2: object_detection / 터미널 4: robot_control — 동일 prologue, 키 불요 ──
#   ros2 run pick_and_place_voice object_detection
#   ros2 run pick_and_place_voice robot_control
```
> `.env` 대안은 설치된 `share/pick_and_place_voice/resource/.env` 를 읽으므로 소스에 두면 재빌드 필요 → 셸 `export` 권장.

- [ ] **Step 2: 검증 (무HW 부분) — 노드 import/asset 무결 기동**

Expected: `object_detection`/`get_keyword`/`robot_control` 셋 다 `ModuleNotFoundError`/`FileNotFoundError`(.pt/.npy/.tflite) 없이 기동. OpenAI 키 없으면 get_keyword 가 키 부재로만 실패해야 함(다른 import 통과 확인).

- [ ] **Step 3: [HW] 검증 — wakeword→STT→LLM→모션 e2e**

마이크 연결 + 키 export 상태에서 "Hello Rokey" → `confidence>0.3` 탐지 → STT 5초 → LLM → 모션. (Task 3 Step 6 의 마이크 검증을 여기서 완결.)

- [ ] **Step 4: Commit** (LAB.md)

```bash
git add scripts/venv-demo/LAB.md
git commit -m "실습 가이드에 voice 데모 실행 절차 추가"
```

---

### Task 8: Part C 정리·대비 + README 반영

**Files:**
- Modify (repo): `scripts/venv-demo/LAB.md` (Part C)
- Modify (repo): `README.md` (데모 진입점 한 단락 + 링크)

**Interfaces:**
- Consumes: 전체 LAB.md.
- Produces: 완성된 LAB.md + README 진입점.

- [ ] **Step 1: LAB.md Part C 작성** (teardown + 대비)

```markdown
## Part C — 정리 & 대비
- 방금 친 명령 수를 세어 본다. **컨테이너 방식이었다면**:
  ```bash
  bash ~/ros2_jazzy_test/containers/bringup.sh mode:=virtual   # 드라이버+카메라
  docker compose -f ~/ros2_jazzy_test/containers/docker-compose.yml up -d   # yolo+voice
  ```
  두 줄. 이미지가 의존성·핀·shim·네임스페이스·빌드를 전부 선처리.
- 정리(원복):
  ```bash
  rm -rf ~/.cobot2_venv_demo
  # (선택) cobot2 원본 되돌리기: rename 역수행 + COLCON_IGNORE 재생성. 비추적이라 git 무관.
  ```

| 관점 | 컨테이너 | venv(이 문서) |
|------|---------|--------------|
| 의존성 설치 | 이미지에 선반영 | 수동 pip(torch 수 GB, numpy<2 순서, openwakeword shim) |
| 네임스페이스 충돌 | FS 격리로 무관 | `robot_control` 등 rename 필요 |
| 마이크/장치 | 이미지+asound.conf | 장치 인덱스 수동 probe |
| 기동 | 2줄 | 7개 터미널·다수 명령 |
| 정리 | `compose down` | `rm -rf` + 원본 원복 |
```

- [ ] **Step 2: README.md 진입점 단락 작성**

README 의 실행/옵션 섹션 근처에 추가(정식 경로 아님 명시):
```markdown
### 컨테이너 없이 실행해 보기 (교육용 대비)

컨테이너 사용 효과를 비교하려면 모놀리식 노드를 host venv 로 직접 실행하는 실습 가이드를 따른다:
[`scripts/venv-demo/LAB.md`](scripts/venv-demo/LAB.md). 의존성 설치·네임스페이스·멀티터미널 기동을
한 줄씩 직접 수행하며, 컨테이너(`bringup.sh` + `docker compose`)가 대신 처리하던 작업량을 체감한다.
정식 설치 경로가 아니라 비교 학습용이다.
```

- [ ] **Step 3: 검증 — teardown 명령 안전성 + README 링크**

Run:
```bash
# teardown 명령이 의도 경로만 지우는지(dry: 경로 확인)
echo "~/.cobot2_venv_demo" && ls -d ~/.cobot2_venv_demo 2>/dev/null || echo "(없으면 정상)"
# README 링크 경로 실제 존재
grep -q "scripts/venv-demo/LAB.md" README.md && test -f scripts/venv-demo/LAB.md && echo "README link OK"
```
Expected: `README link OK`.

- [ ] **Step 4: Commit** (LAB.md + README)

```bash
git add scripts/venv-demo/LAB.md README.md
git commit -m "실습 가이드 정리·대비 섹션과 README 진입점 추가"
```

---

## Self-Review (작성자 점검)

- **Spec coverage**: §4 아키텍처→T1·T5 / §5 rename→T2 / §6 의존성→T4 / §7 Part A→T1–T5 / §8 Part B→T6·T7 / §9 R1·R5·R8→Global+T5·T6 / R2→T3 / R7→T4 / §10 README→T8 / §11 성공기준→T2·T4·T5·T6·T7 검증 / §12 teardown→T8. 누락 없음.
- **placeholder**: T3 의 `device_index: int = N` 은 의도된 [HW] 실측 치환(probe Step 2 가 산출). 그 외 placeholder 없음.
- **type/이름 일치**: 패키지/실행파일명(`pick_and_place_text` detection/robot_move, `pick_and_place_voice` object_detection/get_keyword/robot_control), overlay 경로, venv 경로 전 태스크 일관.
- **커밋 분리**: 각 태스크 LAB.md 단위 커밋, cobot2 변경 미커밋(Global Constraints).
