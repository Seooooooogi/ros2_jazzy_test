# ros2_jazzy_test — Development Roadmap

ROS2 Humble installer → ROS2 Jazzy installer 마이그레이션. 1–4주, solo.

> **검증 원칙 (사용자 결정 2026-05-28)**: 각 Phase 의 **최종 검증 핵심 기준 = `cobot2_ws` 가 정상 동작하는가**.
> `cobot2_ws` (콜콘 워크스페이스: `pick_and_place_voice` = object_detection + voice_processing + robot_control, `od_msg`) 가 해당 Phase 산출 환경에서 빌드/실행되어야 그 Phase 가 "통과"다. shellcheck·정적 검증은 보조 게이트일 뿐, 진짜 acceptance 는 실제 애플리케이션 동작.
> 단 해당 Phase 가 `cobot2_ws` 동작에 영향을 주지 않으면 (순수 문서화·분석 등) 최종 검증은 **생략 가능**.

---

## Phase 1: 현재 humble 셋업 구조 + Docker 계층 파악

**목표**: 마이그레이션 대상의 전체 그림을 먼저 그린다. 코드 수정 금지 단계 — 읽기 / 분석 / 문서화만.

- [x] 1-1. 최상위 스크립트 (`a01` ~ `a06`) 실행 순서 / 의존성 / 부작용 (reboot 등) 매핑 → `MIGRATION_NOTES.md` § 1
- [x] 1-2. `resources/` 하위 install 스크립트 inventory → `COMPATIBILITY.md` humble baseline + `MIGRATION_NOTES.md` § 1
- [x] 1-3. Docker 계층 구조 파악 → 결론: **Dockerfile 없음, host runtime only**. `docker pull hello-world` 는 verification 용 1회 호출 (`MIGRATION_NOTES.md` § 1)
- [x] 1-4. ROS2 Humble 의존성 매트릭스 추출 → `COMPATIBILITY.md` Humble baseline 전체
- [x] 1-5. `docs/COMPATIBILITY.md` 초안 → 생성 완료 (humble 기준 1차, jazzy 라인은 Phase 2 종료 시)
- [x] 1-6. 하드코딩 `humble` / `jammy` (22.04) 문자열 grep → 총 56 라인, 11/14 파일 (`MIGRATION_NOTES.md` § 2)

**Phase 1 산출물**: `docs/COMPATIBILITY.md` (humble 기준), `docs/MIGRATION_NOTES.md` (변경이 필요한 모든 지점 목록)

---

## Phase 2: jazzy 마이그레이션

**목표**: humble 스크립트를 jazzy 기준으로 마이그레이션 + 단일 진입점 통합. humble 스크립트는 삭제 금지 — `backup/` 로 보존.

**진행 구조 (5 milestone, plan 승인 2026-05-27)**: M1 헬퍼 6종 → M2 시스템 레이어 (a01) → M3 컴퓨트/로봇/카메라 (a02) → M4 음성 환경 점검 (a04) → M5 단일 진입점 `install.sh` 통합. 자세한 사항은 `/home/rokey/.claude/plans/phase-1-velvety-dove.md` 참조.

- [ ] 2-1. 공통 config 도입 — `resources/config.sh` 생성, `ROS_DISTRO=jazzy`, `UBUNTU_CODENAME=noble` 등 1회 정의 (Hard Rule #1). venv 관련 변수는 ADR-008 로 폐기.
- [ ] 2-2. 진행률 / 체크포인트 프레임워크 구현 (Hard Rule #3, #4)
  - `[n/total] <step>` 출력 헬퍼
  - `~/.ros2_jazzy_test/state` 에 마지막 성공 단계 기록
  - 재실행 시 state 읽고 다음 단계부터 진행
  - non-interactive 셸용 wrapper `resources/activate.sh` 생성 (ROS2 setup.bash source 만)
- [ ] ~~2-2b. venv 도입~~ — **삭제 (ADR-008, 2026-05-27)**. application Python 은 모두 Phase 4 컨테이너 안. host venv 불필요.
- [ ] 2-3. `set -euo pipefail` 전 스크립트 적용 (Hard Rule #5). pip/setuptools/wheel upgrade 는 host 가 아닌 각 컨테이너 Dockerfile 안 (Phase 4-1/4-2).
- [ ] 2-4. `ros2-install.sh` 마이그레이션 — Ubuntu 22.04 (jammy) → 24.04 (noble), apt repo URL / keyring 갱신
- [ ] 2-5. `nvidia-driver-install.sh` 마이그레이션 — Ubuntu 24.04 NVIDIA 드라이버 호환성 확인
- [ ] ~~2-6. `cuda-pytorch-install.sh` 마이그레이션~~ — **폐기 (ADR-006, 2026-05-29)**. host 에 CUDA toolkit/PyTorch 미설치 (host 콜콘 패키지에 CUDA 소비자 없음, ADR-008). CUDA 12-8 + PyTorch cu128 은 Phase 4 yolo 컨테이너 base image 에서만.
- [ ] 2-7. `docker-install.sh` 마이그레이션 — 베이스 이미지 태그 핀 고정 (`ros:jazzy-ros-base-noble`, Hard Rule #6)
- [x] 2-8. `dsr-project-install.sh` 마이그레이션 (M3, 2026-05-29) — `resources/dsr-project-install.sh` 신규. doosan-robot2 `-b jazzy` clone (idempotent), DSR 전용 apt deps, emulator `3.0.1` 핀 pull. ws = `~/cobot2_ws`, host 패키지(robot_control/od_msg) symlink. 빌드는 `resources/colcon-build.sh`.
- [x] 2-9. RealSense 마이그레이션 (M3, 2026-05-29) — `resources/realsense-sdk-install.sh` (librealsense2 Intel noble apt 정식, vendored 폴백 불필요) + `resources/realsense-ros-install.sh` (`ros-jazzy-realsense2-camera/-description`). `realsense-viewer` 자동실행/`libgtk-3-dev` purge 제거.
- [x] a03. VS Code 마이그레이션 (2026-05-29) — `a03-vs-code-install.sh` 오케스트레이터 + `resources/vscode-install.sh`. 일회성 .deb 다운로드 → Microsoft apt repo + keyring(`packages.microsoft.gpg`, codename 무관 stable main). `code` GUI 자동 실행 제거.
- [x] 2-10. **재정의 (ADR-008 + 사용자 결정 2026-05-27: install.sh = host only)** — 구현 완료 (2026-05-29): `a04-voice-precheck.sh` 오케스트레이터 + `resources/voice-env-check.sh`. host pip install 단계 **전부 제거**, application Python (numpy, langchain, openai, PyAudio, ultralytics, cv2, …) 은 host 가 아닌 yolo/voice 컨테이너 Dockerfile 안에서 설치. a04 는 `.env` 존재·`OPENAI_API_KEY` 점검 + Docker Hub 로그인 안내만 수행 (host 설치 없음).
  - 사용자 결정 "`install.sh` 는 host 만 책임, application(컨테이너) layer 는 `docker compose` 가 책임" 으로 a06 잔여 결정이 **(b) 최소 wrapper 로 좁혀짐**: `.env` placeholder 존재 검증 + Docker Hub login 안내 (ADR-007 의 publish 채택 후 `docker compose pull` 전제 조건). (a) 완전 삭제는 `.env` 검증 손실 위험, (c) launcher 변환은 host/container layer 책임 경계를 다시 흐림 → 둘 다 채택 안 함.
  - ADR-002 (numpy<2 핀) 의 install 순서 원칙 (ultralytics → langchain → numpy 마지막) 은 그대로. 단 적용 위치가 host venv → 컨테이너 Dockerfile 의 마지막 RUN layer (Phase 4-1, 4-2).
- [ ] 2-11. apt keyring 일관성 검사 (Hard Rule #7) — 모든 외부 repo가 `/etc/apt/keyrings/`로 통일됐는지
- [ ] 2-12. State-changing 명령 confirm prompt 추가 (Hard Rule #9) — `sudo reboot` 등에 사용자 확인
- [ ] 2-13. `.env` 로드 패턴 적용 (Hard Rule #10) — OpenAI API key를 스크립트 외부 환경변수에서 받도록
- [ ] 2-14. 전체 스크립트 `shellcheck` 통과 확인
- [ ] 2-15. **M5: 단일 진입점 `install.sh` 통합 (사용자 요청 2026-05-27)**
  - **책임 범위 = host PC layer 만** (사용자 결정 2026-05-27). NVIDIA driver / Docker CE / ROS2 jazzy desktop / DSR colcon 워크스페이스 / librealsense2 SDK + ROS2 wrapper / system Python (apt). **CUDA toolkit 은 host 미설치 (ADR-006/008) — Phase 4 컨테이너 책임**. application(컨테이너) layer 는 **포함하지 않음** — `docker compose pull && docker compose up -d` 는 사용자가 별도 명령으로 실행 (분리 유지).
  - `a0X` 스크립트 본문을 `install.sh` 안에 `step_a01_prerequirements`, ..., `step_a04_voice` 함수로 분리. a04 는 최소 wrapper (2-10 결정) — `.env` placeholder 검증 + Docker Hub login 안내만.
  - `main()` 이 state 헬퍼로 `step_should_skip` 체크 후 순차 호출. 진행률 `[n/total]` 출력
  - reboot 후 `bash install.sh` 재실행 시 state 보고 자동 재개 (Hard Rule #3 resumable 완성)
  - `resources/*.sh` 는 그대로 보존 — `install.sh` 내부에서 source/호출
  - 원본 `a01-a06.sh` 처리는 M5 진입 시 사용자에게 재질문 (삭제 / legacy-split 보관 / symlink)
  - 본 단계 완료 후 ROADMAP 의 "Entry" 및 "순차 실행" 표현을 **2-step setup (host installer → docker compose)** 으로 갱신 + CLAUDE.md Quick Ref 동기화

**Phase 2 산출물**: jazzy 마이그레이션 완료된 스크립트 세트, **단일 진입점 `install.sh`**, `backup/` (보존), `docs/COMPATIBILITY.md` (jazzy 매트릭스 추가), ADR-006 (CUDA 메이저 결정)

---

## Phase 3: jazzy 마이그레이션 트러블슈팅 카탈로그

**목표**: 실제 마이그레이션 중 발생한 문제와 해결법을 카탈로그화. 다음 distro 마이그레이션 시 재참조.

- [ ] 3-1. `docs/TROUBLESHOOTING.md` 작성 — 카테고리별 정리
  - Ubuntu 22.04 → 24.04 패키지 변경 (libgtk-3-dev, libssl, etc.)
  - Python 3.10 → 3.12 호환성 (Cython, build-isolation 변경)
  - **numpy<2 vs numpy>=2 충돌** (ultralytics 핀 vs 신규 라이브러리 기본 설치) — 재현 절차 / 검증 명령 / 알려진 회피책 (`--no-deps`, install 순서) 명시
  - ROS2 humble → jazzy API breaking changes (있다면)
  - CUDA / PyTorch 버전 매트릭스 변경
  - Doosan DSR jazzy 지원 현황 (jazzy 브랜치 부재 시 humble fallback 절차)
  - RealSense SDK Ubuntu 24.04 지원 시점
  - Docker 이미지 ros:humble → ros:jazzy 차이 (베이스 OS, 사전 설치 패키지)
- [ ] 3-2. 신규 워크스테이션에서 jazzy installer end-to-end 검증
- [ ] 3-3. 중단 후 재개 시나리오 검증 — `a02` 중간 실패 → 재실행 시 마지막 성공 단계 다음부터 진행하는지 (Hard Rule #3)
- [ ] 3-4. `docs/decisions/` 에 마이그레이션 중 내린 주요 결정 ADR로 기록 (예: "DSR jazzy 미지원 시 어떻게 처리했는가")

**Phase 3 산출물**: `docs/TROUBLESHOOTING.md`, 추가 ADR

---

## Phase 4: 애플리케이션 컨테이너화 (사용자 요청 2026-05-27)

**목표**: host 에 설치된 jazzy 환경 위에서 두 개의 독립 마이크로서비스를 Docker container 로 분리 실행. 두 컨테이너는 **ROS2 service server** (yolo = `/get_3d_position`, voice = `/get_keyword`) 로 host 의 `robot_control` 노드(client)에 응답한다. yolo 컨테이너는 `realsense2_camera` 노드를 자체 포함해 USB 카메라를 직접 열고 (`--device` passthrough) `/camera/camera/*` 를 컨테이너 안에서 publish/subscribe 한다.

**책임 분리 원칙 (사용자 결정 2026-05-27)**:
- **System (host) layer = `bash install.sh`** — NVIDIA driver / Docker CE / ROS2 jazzy / DSR colcon 워크스페이스 / RealSense SDK (CUDA toolkit 은 host 미설치 — Phase 4 컨테이너, ADR-006/008)
- **Application (container) layer = `docker compose pull && docker compose up -d`** — yolo / voice image
- 두 layer 의 책임이 명시적으로 분리되어 신규 노트북 셋업 흐름은 **2-step**:
  ```bash
  bash install.sh                    # host 시스템 layer 완성 (필요 시 reboot 후 재실행)
  docker login                       # Docker Hub PAT (ADR-007)
  docker compose pull                # publish 된 image 통팩 (없으면 build --pull 으로 fallback)
  docker compose up -d               # 컨테이너 layer 기동
  ```

**의도된 아키텍처** (사용자 결정 2026-05-27, service 기반 구조 확정 2026-05-28):
```
[host (Ubuntu 24.04 + ROS2 jazzy)]
  robot_control 노드 (pick_and_place) ──client──► 아래 두 service
  DSR control 노드 (dsr_bringup2) ──DSR_ROBOT2 API / TCP 12345──► 실기 Cobot
        ▲ service response            ▲ service response
        │                             │
[voice-processing 컨테이너]      [yolo-detection 컨테이너]
 service server /get_keyword      service server /get_3d_position
   (std_srvs/Trigger)               (od_msg/SrvDepthPosition)
 langchain + openai + PyAudio     PyTorch + CUDA + ultralytics
 openwakeword + tflite-runtime    cv_bridge + od_msg
 rclpy (ROS2 노드)                 realsense2_camera + object_detection (컨테이너 내부 /camera/camera/*)

모두 network_mode: host + 동일 ROS_DOMAIN_ID / RMW_IMPLEMENTATION (DDS discovery)
```
> topic publisher 가 아니라 **service server** 다 — yolo/voice 는 robot_control 의 요청에 응답하는 구조. RealSense 카메라는 yolo 컨테이너가 USB passthrough 로 직접 열고 자기 안에서 처리한다 (host realsense 노드 아님). udev rule·커널 모듈만 host 에 둔다.

- [ ] 4-1. `containers/yolo-detection/Dockerfile` + 빌드 스크립트 (cobot2_ws `object_detection` + `realsense2_camera`)
  - Base: `ros:jazzy-ros-base-noble` 명시 핀 (Hard Rule #6)
  - **역할 = service server** `/get_3d_position` (`od_msg/SrvDepthPosition`). client 는 host 의 `robot_control` 노드. topic publish 아님 — request/response 구조.
  - **카메라 = 컨테이너 자체 포함** (구조 결정 2026-05-28, 기존 host-side 안에서 변경): `realsense2_camera` 노드를 yolo 컨테이너 안에서 실행 → USB 직접 열고 `/camera/camera/*` 를 컨테이너 안에서 publish, `object_detection` 의 ImgNode 가 같은 topic subscribe. 근거 = workflow 단순화 + 카메라/추론 한 이미지로 자기완결 배포.
  - **USB device passthrough 필요**: 4-3 docker-compose 에 `--device /dev/bus/usb`. udev rule·커널 모듈은 host 책임 (컨테이너로 못 옮김 — a02 설치).
  - 내부: ultralytics + PyTorch (cu${CUDA_VERSION}) + opencv-python + `cv_bridge` + `ros-jazzy-realsense2-camera` + librealsense2 runtime + `od_msg` (custom interface)
  - **GPU 패스스루**: NVIDIA Container Toolkit 의존 (host a01 에서 driver 설치되어 있다는 전제)
  - 모델 가중치 / 설정은 volume mount (image 안에 안 박음)
  - **`od_msg` 빌드 정합성**: yolo 컨테이너 + host(robot_control) + voice 가 동일 `od_msg` 정의를 빌드해야 service type hash 일치. 단일 source = `cobot2_ws/od_msg`
- [ ] 4-2. `containers/voice-processing/Dockerfile` + 빌드 스크립트 (cobot2_ws `voice_processing` 패키지)
  - Base: `ros:jazzy-ros-base-noble` 명시 핀
  - **역할 = service server** `/get_keyword` (`std_srvs/Trigger`). client 는 host 의 `robot_control` 노드. wake-word 발화 → STT → keyword 추출 결과를 response 로 반환.
  - 내부: langchain + langchain-openai + openai + PyAudio + openwakeword + tflite-runtime + sounddevice
  - **오디오 입력 소스 = 노트북 내장 마이크** (USB 외장 마이크 아님, 사용자 결정 2026-05-27)
  - 권장 audio passthrough: **PulseAudio / PipeWire socket mount** (Ubuntu 24.04 기본 PipeWire 와 호환). raw ALSA (`/dev/snd`) 는 desktop session 의 mixer 와 충돌 위험 + 디바이스 번호 환경 의존성. PipeWire 데몬 경유가 안전.
  - mount 패턴 후보:
    ```yaml
    volumes:
      - ${XDG_RUNTIME_DIR}/pulse:/run/user/1000/pulse:ro
      - ${HOME}/.config/pulse/cookie:/root/.config/pulse/cookie:ro
    environment:
      - PULSE_SERVER=unix:/run/user/1000/pulse/native
    ```
  - host 측 사전 조건: Ubuntu 24.04 desktop 의 PipeWire 데몬이 user session 에 실행 중 (기본). 내장 마이크가 `pactl list sources short` 에 인식되는지 a04 (또는 Phase 4 진입 검증) 에서 확인.
  - **API key 전달**: `.env` 를 docker-compose 의 `env_file:` 로 mount, image 안에 박지 않음 (Hard Rule #10)
- [ ] 4-3. `containers/docker-compose.yml` — 두 서비스 동시 start/stop
  - 각 서비스의 image 태그 명시 (ADR-007): `docker.io/${DOCKERHUB_USER}/ros2-jazzy-yolo:${YOLO_TAG}`, `docker.io/${DOCKERHUB_USER}/ros2-jazzy-voice:${VOICE_TAG}`. `${DOCKERHUB_USER}`, `${YOLO_TAG}`, `${VOICE_TAG}` 는 host `.env` 로부터 주입
  - `restart: unless-stopped` 정책
  - GPU 사용 (yolo 만): `deploy.resources.reservations.devices` 또는 `runtime: nvidia`
  - **API key 등 secret 은 `environment:` runtime 주입만** (ADR-007 § 4) — image 안에 placeholder 도 안 박음. `env_file: .env` 또는 `environment: - OPENAI_API_KEY=${OPENAI_API_KEY}` 패턴
  - **DSR emulator 서비스 (`doosanrobot/dsr_emulator:3.0.1`)**: 거의 미사용 가정 (2026-05-27 사용자 결정 — 실기 우선). 기본 `docker compose up` 에 포함하지 않고 `profiles: [dev]` 로 격리. 개발 모드에서만 `docker compose --profile dev up` 으로 활성화. 설치 흐름의 `install_emulator.sh` 호출은 그대로 — 이미지는 받아두되 실행은 명시적
- [ ] 4-4. ROS2 통신 패턴 결정 (별도 ADR 후보 — ADR-007 은 publish 결정으로 점유됨)
  - 후보 (a) `network_mode: host` — DDS multicast 자연 동작, 보안↓
  - 후보 (b) custom bridge + `ROS_DOMAIN_ID` 격리 — 보안↑, DDS discovery 설정 필요
  - 후보 (c) `host` 와 동등하나 명시적 (`--network host` + ROS_DOMAIN_ID 고정)
  - host↔container 통신 = 2개 service (`/get_3d_position`, `/get_keyword`) request/response (DDS). camera topic (`/camera/camera/*`) 은 yolo 컨테이너 내부 (realsense → object_detection). `network_mode: host` 가 service discovery 커버.
  - DSR 에뮬레이터 (`doosanrobot/dsr_emulator:3.0.1`) 도 같은 네트워크 안인지 결정
- [ ] 4-5. Image 태그 핀 + reproducibility (Hard Rule #6, ADR-007 정합)
  - Base image (`ros:jazzy-ros-base-noble`) 명시 태그, 절대 `latest` 금지
  - 본 레포 자체 image 명명 (ADR-007): `docker.io/${DOCKERHUB_USER}/ros2-jazzy-yolo:<tag>`, `docker.io/${DOCKERHUB_USER}/ros2-jazzy-voice:<tag>`
  - Tag 정책: semver 1차 (`v0.1.0`), git short SHA 2차 (7 char). `latest` 금지
  - **Docker Hub public publish 채택 (ADR-007)** — 단 publish 전 mandatory secret hygiene 검증 (`docker history --no-trunc | grep -iE 'OPENAI|API_KEY|TOKEN|SECRET'` 결과 0 건)
  - 빌드 명령 wrapper (예: `containers/build-all.sh`) 신설 — `docker compose build --pull` + secret hygiene grep 자동화
- [ ] 4-6. host installer 와의 통합 — **수동 호출 분리 유지로 결정 (사용자 2026-05-27)**
  - `install.sh` (M5 산출) 는 host layer 완성 후 종료. `docker compose pull / up -d` 는 사용자가 별도 명령으로 실행.
  - 이유: install.sh 가 host + 컨테이너 layer 양쪽을 책임지면 비대해지고 디버깅 시 layer 분리 어려움. 본 레포 사용자 수가 적어 (~5 노트북) 2-step 명령 인지 비용 < 책임 분리 이득.
  - README / CLAUDE.md Quick Ref 의 진입점 표현을 2-step (host installer → docker compose) 으로 명시.
  - ADR-007 §5 의 pull-first 분기 (`docker manifest inspect` 성공 시 pull, 실패 시 build) 는 별도 wrapper 스크립트 (`containers/up.sh` 등) 에 캡슐화 — 사용자가 한 명령으로 호출 가능하되 install.sh 와는 독립.
- [ ] 4-7. **이미지 빌드 + secret hygiene 검증 + Docker Hub publish + 종단 검증 (ROADMAP 종착점)**
  - `docker compose build --pull` 양쪽 이미지 빌드 → exit 0
  - 빌드 산출물 검증: `docker image ls` 에서 `ros2-jazzy-yolo:<tag>`, `ros2-jazzy-voice:<tag>` 존재 + size sanity check (yolo 5GB 이하, voice 2GB 이하 등 — 베이스 이미지 + 의존성 합 기준)
  - **Secret hygiene mandatory 검증 (ADR-007 § 4)**:
    ```bash
    for img in ros2-jazzy-yolo ros2-jazzy-voice; do
        docker history --no-trunc "${img}:${TAG}" \
          | grep -iE 'OPENAI|API_KEY|TOKEN|SECRET' \
          && { echo "LEAK in $img"; exit 1; } || echo "$img clean"
    done
    ```
    match 1건이라도 발견 시 publish 차단 + Dockerfile 수정 후 재빌드
  - **Docker Hub publish (ADR-007)**:
    ```bash
    docker login -u "${DOCKERHUB_USER}"   # PAT 사용, 평문 password 금지
    docker tag ros2-jazzy-yolo:<tag> docker.io/${DOCKERHUB_USER}/ros2-jazzy-yolo:<tag>
    docker tag ros2-jazzy-voice:<tag> docker.io/${DOCKERHUB_USER}/ros2-jazzy-voice:<tag>
    docker push docker.io/${DOCKERHUB_USER}/ros2-jazzy-yolo:<tag>
    docker push docker.io/${DOCKERHUB_USER}/ros2-jazzy-voice:<tag>
    ```
  - `docker compose up -d` → 두 서비스 healthy (DSR emulator 는 `--profile dev` 로 옵트인)
  - **ROS2 topic flow 검증**:
    - YOLO 컨테이너 GPU 인식: `docker exec ros2-jazzy-yolo python3 -c "import torch; assert torch.cuda.is_available()"`
    - YOLO publish: host 에서 `ros2 topic echo /detect/bbox` 로 1+ msg 수신
    - Voice publish: host 에서 `ros2 topic echo /voice/text` 로 wake-word 발화 후 1+ msg 수신
  - **신규 노트북 통팩 검증** (ADR-007 § 5): 다른 노트북에서 host installer 완료 후 `docker compose pull && docker compose up -d` 로 빌드 없이 동일 환경 재현 → ROS2 topic flow 동일 PASS
  - 위 검증 PASS = 본 ROADMAP 전체 완료. `docs/COMPATIBILITY.md` 에 jazzy 최종 매트릭스 + Docker image 기록 (publish 된 image digest 포함).

**Phase 4 산출물**:
- `containers/yolo-detection/Dockerfile` + 부속 (entrypoint, requirements, `.dockerignore`)
- `containers/voice-processing/Dockerfile` + 부속 (`.dockerignore`)
- `containers/docker-compose.yml` (image 태그 = ADR-007 publish target, secret 은 runtime env 주입)
- `containers/build-all.sh` (빌드 wrapper — `docker compose build --pull` + secret hygiene grep 자동화)
- `containers/up.sh` (pull-first 분기 wrapper — ADR-007 § 5)
- **ADR-009 (가칭)** — Phase 4 base image 선택 / ROS2 네트워크 모드 / install.sh 통합 결정 (현재 Open Decisions 의 (a)(b)(c))
- Docker Hub publish 된 두 image (ADR-007): `docker.io/${DOCKERHUB_USER}/ros2-jazzy-yolo:<tag>`, `docker.io/${DOCKERHUB_USER}/ros2-jazzy-voice:<tag>`
- `.env.example` 갱신: `DOCKERHUB_USER`, `DOCKERHUB_TOKEN`, `YOLO_TAG`, `VOICE_TAG` placeholder 추가
- `docs/COMPATIBILITY.md` 의 Docker 섹션에 두 image 행 추가 (publish digest 포함) + jazzy 최종 매트릭스

---

## Backlog (unscheduled)

- [ ] jazzy → 차기 distro (kilted/lyrical) 자동 마이그레이션 도우미 스크립트
- [ ] Docker 이미지 빌드 자동화 — installer 결과를 Docker 이미지로 재현 가능하게
- [ ] CI 통합 — 매 커밋마다 shellcheck + (가능하면) container에서 dry-run 검증
- [ ] ROS distro 별 multi-target 빌드 (humble + jazzy 양쪽 유지보수 모드)
