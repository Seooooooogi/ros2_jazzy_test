# Docker YOLO 컨테이너 직접 구축 실습 (Hands-on Lab) — 설계 (Design Spec)

- **날짜**: 2026-07-13
- **상태**: Draft (사용자 검토 대기) — **본문의 `/opt/venv` 절차는 2026-07-20 ADR-034 로 superseded**(컨테이너 내부 venv 폐기 → `pip --break-system-packages`). 아래 venv 서술은 당시 스냅샷으로 보존. 현행 절차는 `containers/yolo-detection/Dockerfile` 과 설치 매뉴얼 §17.
- **관련**: `containers/yolo-detection/Dockerfile` (정답지), `containers/build-all.sh` (자동 빌드·smoke), `resources/dds-tuning.sh` (cyclonedds — 유지), `resources/config.sh` (`ROS_DISTRO`/`YOLO_WS`/`CUDA_VERSION` 단일 소스), `docs/TRAINEE_PRACTICE_PATH.md`, ADR-016/ADR-020 (DDS/RMW)

---

## 1. 목적 (Goal)

초급 교육생이 **공식 `ros:jazzy-ros-base-noble` 을 pull → `docker run -it` 로 진입 → 라이브러리를 직접 설치·환경설정 → `docker commit` 으로 이미지화**하는 과정을 손으로 밟아 Docker 를 체득한다. 최종 결과물은 `build-all.sh` 가 자동으로 만들던 yolo 환경과 **동등**한, 실제 구동 가능한 이미지.

핵심 학습 가치는 "명령을 직접 쳐서 컨테이너를 만들어 보는 경험" + "컨테이너=일회성 / 이미지=재현물" 개념 + "numpy<2 같은 의존성 함정을 손으로 밟아 이해". 자동화(`setup-app.sh`)는 학습이 끝난 뒤의 **빠른 재설치** 수단으로 남는다.

## 2. 워크플로우 내 위치

```
install.sh (host 기반)
  → 워크스페이스 배치 (README step 3)
  → [venv 랩, 추후 추가]
  → ★ Docker 랩 (이 설계 — 학생이 yolo 이미지를 손으로 구축)
  → setup-app.sh (학습 후 빠른 재설치)
```

## 3. 확정 결정 (Decisions)

| 항목 | 결정 | 근거 |
|------|------|------|
| 실습 모델 | **인터랙티브 전용 + `docker commit`** | "명령을 직접 입력하는 경험" 이 목적. Dockerfile 작성은 범위 밖(추후 심화 가능). |
| base 이미지 | **공식 `ros:jazzy-ros-base-noble`** | 이미 Docker Hub 공식 + yolo Dockerfile 의 실제 FROM. 발행 불필요. 학생이 colcon/rosdep 까지 직접 설치 → 학습량 ↑. |
| 산출물 구조 | **runbook 문서 + verify 스크립트** | 자동 자가검증(Gate 1)을 학생이 한 줄로 돌릴 수 있게. |
| 재현 충실도 | **간소화** (venv on PATH, `--system-site-packages`) | 노드는 정상 구동하되 프로덕션 Dockerfile 의 PYTHONPATH/멀티스테이지 트릭은 callout 로만 설명. |
| cyclonedds | **install.sh 에 유지** — 랩에서는 "이해·점검" 만 (부록) | cyclonedds 는 컨테이너 leaf 산출물이 아니라 host 공용 기반(§7). |
| nvidia-container-toolkit | **install.sh 통합 안 함** — 랩에서 학생이 직접 설치 (Gate 2 선행), `setup-app.sh` 자동 설치는 유지 | 컨테이너 전용 + 개념 명료(GPU passthrough shim) → docker 학습 소재. host 기반 아님(§7.1). |

## 4. 랩 문서 — `docs/DOCKER_LAB.md`

한국어 설명 + 영어 식별자. 복붙 가능한 명령 블록 + 각 단계 "= yolo Dockerfile 몇 줄에 해당" 매핑 + "왜 이 핀인가" 짧은 설명.

### 4.1 전제 (선행)
- `bash install.sh` 완료 (Docker + host ROS2 + **cyclonedds 튜닝** 포함).
- cobot2 소스 배치 완료 → `~/cobot_ws/src/cobot2/yolo_container` 에 `od_msg` + `object_detection` 존재 (README step 3). 랩은 이 소스를 bind-mount 만 하므로 host colcon build 는 불요.
- (Gate 2 = 실제 추론 시에만) NVIDIA Container Toolkit(§4.4 에서 학생이 직접 설치) + host RealSense 토픽 + 학습된 `best.pt`.

### 4.2 본문 단계 (interactive → commit)

각 단계는 `yolo-detection/Dockerfile` 의 **builder 스테이지**를 손으로 옮긴 것.

1. **pull**: `docker pull ros:jazzy-ros-base-noble`
2. **run (진입)**:
   ```bash
   docker run -it --name yolo-lab -w /ws \
     --network host \
     -e ROS_DISTRO=jazzy -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
     -e ROS_DOMAIN_ID=0 -e CYCLONEDDS_URI=file:///cyclonedds.xml \
     -v ~/.config/cyclonedds/cyclonedds.xml:/cyclonedds.xml:ro \
     -v ~/cobot_ws/src/cobot2/yolo_container:/ws/src \
     ros:jazzy-ros-base-noble bash
   ```
   (`--gpus all` 은 Gate 2 에서만 추가 — import smoke 는 GPU 불요)
3. **apt (빌드/런타임 의존)** — 컨테이너 안:
   ```bash
   apt-get update && apt-get install -y --no-install-recommends \
     build-essential python3-dev python3-venv python3-pip \
     python3-colcon-common-extensions python3-rosdep \
     ros-$ROS_DISTRO-rosidl-default-generators \
     ros-$ROS_DISTRO-cv-bridge ros-$ROS_DISTRO-sensor-msgs \
     ros-$ROS_DISTRO-rmw-cyclonedds-cpp
   ```
4. **venv (간소화 — PATH 에 올림)**:
   ```bash
   python3 -m venv --system-site-packages /opt/venv
   source /opt/venv/bin/activate
   pip install --upgrade pip
   ```
5. **torch (cu128, 가장 무거운 단계)**:
   ```bash
   pip install --index-url https://download.pytorch.org/whl/cu128 \
     torch==2.11.0 torchvision==0.26.0
   ```
6. **ultralytics + numpy 함정 (핵심 교훈)**:
   ```bash
   pip install "ultralytics<9" "opencv-python<4.10"
   pip install --force-reinstall "numpy<2"
   python3 -c "import numpy; assert numpy.__version__.startswith('1.'), numpy.__version__; print('numpy', numpy.__version__)"
   ```
7. **colcon build (od_msg → object_detection)**:
   ```bash
   rosdep init 2>/dev/null || true; rosdep update
   source /opt/ros/$ROS_DISTRO/setup.bash
   rosdep install --from-paths src --ignore-src --rosdistro "$ROS_DISTRO" -y \
     --skip-keys "ultralytics numpy"
   colcon build --merge-install          # symlink-install 아님 — commit 후 /ws/src 없이도 import 가능해야
   source install/setup.bash
   ```
8. **노드 구동 확인**: `ros2 run object_detection object_detection` (Ctrl+C 로 종료)
9. **이미지화 (host 새 터미널)**:
   ```bash
   docker commit --change 'ENV PATH=/opt/venv/bin:$PATH' yolo-lab my-yolo:lab
   ```
   `--change ENV PATH` = 커밋 이미지에서 `python3` 가 venv 를 가리키게 (fresh `docker run` 은 activate 를 안 하므로). 이것도 docker 학습 포인트.
10. **재기동 검증**: `bash containers/lab/verify.sh my-yolo:lab` (아래 Gate 1).

**커밋 관련 필수 주의 (문서에 명시)**: `/ws/src` 는 bind-mount 라 `docker commit` 에 **안 담긴다**. 그래서 `--merge-install`(모듈을 `/ws/install` 로 복사)이어야 소스 없이도 노드가 돈다. `--symlink-install` 이면 install 이 사라진 `/ws/src` 를 가리켜 커밋 이미지가 깨진다.

### 4.3 검증 게이트 (2단)

- **Gate 1 — 환경 구축 성공 (필수, 하드웨어 불요)**: `containers/lab/verify.sh` 가 커밋 이미지에서 import smoke 통과. GPU/카메라/모델 불요. 대부분의 학생이 여기까지 도달하면 "성공".
- **Gate 2 — 실제 추론 (선택, GPU+카메라+`best.pt`)**: **선행 = §4.4 NVIDIA Container Toolkit 설치** → `--gpus all` + host RealSense + 모델 마운트로 `object_detection` 노드가 `/get_3d_position` 서비스 제공. 기존 `README.md`/`TRAINEE_PRACTICE_PATH.md` Step 3 절차로 연결.

### 4.4 NVIDIA Container Toolkit — Gate 2 선행 (수동 설치, 학습)

Gate 2(실제 GPU 추론) 직전, 학생이 직접 설치하며 "왜 GPU 컨테이너에 이 shim 이 필요한가" 를 배운다. install.sh 에 통합하지 않는 이유는 §7.1.

- **개념**: base 이미지엔 CUDA·`nvidia-smi` 가 없다. toolkit = host driver 라이브러리 + `/dev/nvidia*` 장치를 컨테이너에 주입하는 runtime shim. 이게 있어야 `--gpus all` / compose 의 nvidia device reservation 이 동작.
- **명령** (host):
  ```bash
  sudo install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor -o /etc/apt/keyrings/nvidia-container-toolkit.gpg
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/etc/apt/keyrings/nvidia-container-toolkit.gpg] https://#' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
  sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker      # daemon 재시작 — 실행 중 컨테이너 잠깐 멈춤(학생이 직접 = 명시적 동의)
  ```
- **검증 (aha 모먼트)**: base 이미지엔 `nvidia-smi` 가 없는데 toolkit 이 host 것을 주입 →
  ```bash
  docker run --rm --gpus all ros:jazzy-ros-base-noble nvidia-smi
  ```
  GPU 표가 뜨면 성공.
- **정답지**: `resources/nvidia-container-toolkit-install.sh` 가 위 과정을 멱등·검증까지 자동화(키링 signed-by, `SKIP_IF_NO_GPU`, nvidia runtime 재등록 확인). `setup-app.sh` 빠른 경로가 이걸 사용. 학생은 손으로 한 뒤 이 스크립트와 대조.

> **검토 메모**: 명령을 공식 절차로 직접 타이핑 vs `resources` 스크립트 참조 비중은 검토 단계에서 조정.

### 4.5 부록 A — cyclonedds 이해·점검 (생성 아님)

install.sh 가 이미 만든 것을 **왜 쓰는지** 설명 (제거하지 않음, §7 참조):
- `~/.config/cyclonedds/cyclonedds.xml` 을 열어보고 NIC 화이트리스트·버퍼가 무엇인지 관찰.
- 랩 `docker run` 의 `-v cyclonedds.xml:ro` / `-e CYCLONEDDS_URI` / `-e RMW_IMPLEMENTATION` / `--network host` 4개가 **왜 짝을 이뤄야** host↔컨테이너 토픽이 보이는지 (하나만 어긋나도 discovery 실패).
- 원하면 `bash resources/dds-tuning.sh` 를 직접 재실행해 동작 관찰 (멱등이라 안전).
- 참고: `ROS_DOMAIN_ID` 는 이미 학생 과제로 위임돼 있음(`~/.bashrc` 에 직접 추가) — "안전·바운드된 조각만 학생에게" 패턴.

> **검토 메모**: 이 부록은 사용자 검토 후 수정 예정. 설명 범위·깊이·재실행 권장 여부를 검토 단계에서 조정.

## 5. verify 스크립트 — `containers/lab/verify.sh`

- **역할**: 학생이 커밋한 이미지가 타깃 환경과 일치하는지 자동 대조 (Gate 1). `build-all.sh` 의 `smoke()` 를 학생용으로 추출.
- **인터페이스**: `bash containers/lab/verify.sh [IMAGE_TAG]` (기본 `my-yolo:lab`).
- **동작**: `docker run --rm "$IMAGE" bash -c '<smoke>'` 로
  - ROS setup + `/ws/install/setup.bash` source, venv site-packages 를 PYTHONPATH 로 주입(venv 가 PATH 에 있든 없든 견고 — build-all 과 동일 로직),
  - `import torch, torchvision, ultralytics, cv2, numpy`
  - `from od_msg.srv import SrvDepthPosition`
  - `import object_detection.yolo, object_detection.realsense, object_detection.detection`
  - `assert numpy.__version__.startswith('1.')`
  - 통과 시 `✅ PASS`, 실패 시 어느 import 가 깨졌는지 + `❌ FAIL` 비-0 종료.
- **규약**: `set -euo pipefail`, `$ROS_DISTRO` 는 컨테이너 안에서 읽음(distro 문자열 하드코딩 금지 — Hard Rule #1), shellcheck 통과.
- **비-역할**: 런타임 배선(GPU/카메라/서비스 왕복)은 검사하지 않음 — 그건 Gate 2(하드웨어 필요). build-all.sh 가 GPU/model/서비스를 host e2e 로 미룬 것과 동일 철학.

## 6. README 변경

`README.md` 학습 순서에 Docker 랩 1줄 포인터 추가 (host install → 워크스페이스 → (venv 추후) → **Docker 랩** → setup-app 빠른 경로). 기존 실행 절차는 그대로.

## 7. cyclonedds 를 install.sh 에 유지하는 근거 (검토 기록)

랩으로 옮기지 **않는** 이유 (yolo 이미지와 성격이 반대):

1. **`dds-tuning.sh` 는 xml 하나가 아니다** — 물리 NIC 자동 감지 + `sudo` sysctl 커널 버퍼(`/etc/sysctl.d/60-cyclonedds.conf`) + xml 렌더 + `~/.bashrc` managed block 4가지. sudo·커널·동적 NIC 는 "docker 명령 실습" 과 성격이 다르고, NIC 오선택 시 discovery 가 조용히 실패.
2. **소비자가 컨테이너가 아니라 host** — DSR 드라이버·RealSense 가 대용량 토픽에 커널 버퍼+xml 필요(없으면 노드 `exit -6`, `TROUBLESHOOTING.md:101`). `setup-app.sh` 의 colcon build 도 cyclonedds RMW 전제(`colcon-build.sh:43`). yolo 컨테이너는 host 파일을 read-only mount + `network_mode: host` 로 커널 버퍼를 **상속하는 하위 소비자**일 뿐.
3. **워크플로우상 랩보다 먼저 필요** — calibration 등 컨테이너 무관 host 작업도 cyclonedds 의존. 랩에만 넣으면 랩을 건너뛴 경로에서 host ROS2 가 깨진다.

## 7.1 nvidia-container-toolkit 를 랩 수동으로 두는 근거 (검토 기록)

cyclonedds 와 **반대 결론** — 같은 원칙("host 공용 기반은 자동화, 컨테이너 전용·개념 명료한 건 학생 수동")의 다른 쪽:

1. **컨테이너 전용** — 스크립트 헤더가 명시: "GPU 컨테이너 구성에서만 필요, host-only 는 불필요"(`SKIP_IF_NO_GPU` 존재). host ROS2/DSR/RealSense/colcon 무관 → install.sh base 에 넣으면 scope creep.
2. **개념이 명료·typeable** — repo/key → `apt install` → `nvidia-ctk runtime configure` → docker restart. "GPU passthrough shim" 이 docker 학습 목표 그 자체. cyclonedds(불투명 동적 NIC + 커널 sysctl)와 대비.
3. **daemon 재시작** — 되돌릴 수 없어 명시 동의 필요(Hard Rule #9). 자동 시퀀스에 넣으면 `ASSUME_YES` 강제 필요. 학생이 손으로 `restart docker` = 자연스러운 명시 동의.

→ install.sh 통합(A) 기각. `setup-app.sh` 자동 설치는 빠른 경로용으로 유지.

## 8. 산출물 (Deliverables)

| 파일 | 유형 | 내용 |
|------|------|------|
| `docs/DOCKER_LAB.md` | 신규 | §4 runbook (본문 + Gate 2 toolkit 수동 설치 + 2 게이트 + cyclonedds 부록) |
| `containers/lab/verify.sh` | 신규 | §5 Gate 1 자가검증 스크립트 |
| `README.md` | 수정 | §6 학습 순서에 Docker 랩 포인터 1줄 |
| `docs/specs/2026-07-13-docker-yolo-hands-on-lab-design.md` | 신규 | 본 설계 문서 |

## 9. 비목표 / 범위 밖 (Non-goals)

- **venv 랩** (워크플로우 3단계) — 추후 별도 설계.
- **Dockerfile 작성 실습** — 인터랙티브 모델로 확정. 심화로 나중에 추가 가능.
- **프로덕션 멀티스테이지 완전 재현** (venv off-PATH + PYTHONPATH 주입 + 슬리밍) — callout 설명만.
- **Docker Hub 이미지 발행** — base = 공식 이미지라 불필요.
- **cyclonedds 를 install.sh 에서 제거** — 유지 확정(§7).
- **nvidia-container-toolkit 를 install.sh 에 통합(A)** — 기각(§7.1). 랩 수동 + `setup-app.sh` 자동 유지.
- **voice** — host 직접 실행(ADR-027), 이 랩과 무관.
- **`containers/template/` 정리** — 이 랩이 공식 base 를 쓰면서 미사용이 되지만, 삭제는 별건.

## 10. Hard Rules / 호환성 영향

- **#1 distro 단일 소스**: 문서·verify.sh 는 `$ROS_DISTRO` 참조(예시에 jazzy 노출은 가독성용, 로직 하드코딩 아님).
- **#6 이미지 태그 핀**: `ros:jazzy-ros-base-noble` 명시 태그, `latest` 없음.
- **#5 `set -euo pipefail`**: verify.sh 진입점에 적용.
- **#10 secrets**: yolo 는 OPENAI 키 불요 — 랩 전 과정에 자격증명 없음.
- **COMPATIBILITY.md 변경 없음**: torch 2.11.0 / cu128 / ultralytics<9 / opencv<4.10 / numpy<2 모두 기존 매트릭스 값 재인용(신규 버전 도입 없음).
