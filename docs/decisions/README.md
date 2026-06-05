# Architecture Decision Records

본 프로젝트의 구조를 결정한 선택을 기록한다. 새 의존성 추가, 기존 패턴 교체, 시스템 인터페이스 변경, 마이그레이션 중 우회 결정이 발생할 때마다 새 ADR을 추가한다.

## Template

```markdown
# ADR-NNN: [제목]

## Context
이 결정이 필요한 배경과 제약.

## Decision
무엇을 선택했는가.

## Consequences
트레이드오프, 알려진 제약, 후속 영향.
```

---

## Decisions

### ADR-001: Initial Stack & Hard Rules

**Context**: `/project-init` 인터뷰로 humble installer → jazzy installer 마이그레이션 프로젝트의 초기 스택과 invariants를 결정.

**Decision**:
- Language: Bash (Ubuntu/ROS2 installer 도메인 표준)
- Data: None (패키지 설치만)
- Interface: CLI only (`bash a0X-*.sh` 순차 실행)
- Deployment: Local — 각 워크스테이션에서 1회 실행
- AI features in installer logic: None (Voice 스크립트는 외부 LLM 라이브러리 "설치"만 수행)

**Hard Rules origin (11개)**:
1. **ROS distro 단일 진실 소스** — 이 프로젝트의 본질이 distro 마이그레이션이므로 distro 문자열 하드코딩이 가장 비싼 부채.
2. **Idempotency** — installer 도메인 표준. 재실행 시 환경 오염 방지.
3. **Resumable installer** — 단계별 설치(`a01`~`a06`)에서 중간 실패가 빈번. 처음부터 재시작은 시간 낭비 (드라이버 재설치 등 10분 이상 소요 단계 존재).
4. **설치 진행률 시각화** — 현재 스크립트가 어디서 멈췄는지 추적 불가 → 사용자 혼란.
5. **`set -euo pipefail`** — bash 표준 안전장치. 의존성 누락 상태로 다음 단계 진입 방지.
6. **Docker 이미지 태그 핀 고정** — `latest` 태그가 silent drift 하면 마이그레이션 검증 무력화.
7. **apt repo 키링 일관성** — `apt-key` deprecated, Ubuntu 24.04에서 경고 발생. 신규 distro 마이그레이션 기회에 일관화.
8. **버전 호환 매트릭스** — Ubuntu/ROS/CUDA/PyTorch/DSR 조합 폭발. 검증된 조합만 추적 가능하게.
9. **State-changing confirm** — `sudo reboot`가 무경고 실행되어 사용자 작업 손실 사례 방지.
10. **No hardcoded secrets** — Voice 단계 OpenAI key 유출 방지.
11. **No AI attribution in git** — git history 비가역. 사전 차단이 유일한 방어.

**Consequences**:
- Hard Rule #3 (resumable)을 구현하려면 state file 포맷과 단계 식별자 컨벤션을 Phase 2 시작 전에 확정해야 함.
- Hard Rule #1 (distro 변수화) 적용 시 기존 humble 스크립트는 `backup/` 으로 이동 (2026-05-27 사용자 결정으로 폴더명 확정) — Phase 1 산출물인 `docs/MIGRATION_NOTES.md`에서 diff 가능하도록 보존.
- Hard Rule #6 (Docker tag pinning) 때문에 ROS2 Jazzy 공식 이미지 태그 고정값 (`ros:jazzy-ros-base-noble` 등) 을 Phase 1에서 결정하고 별도 ADR로 기록 예정.

---

### ADR-002: numpy 버전 핀 — ultralytics 호환성

**Context**:
- `a06-Voice.sh` 기존 코드가 `numpy==1.24.4 --ignore-installed`로 강제 다운그레이드 — humble (Python 3.10) 시절 흔적.
- Ubuntu 24.04 / Python 3.12 환경에서 `numpy 1.24.x`는 호환 안 됨 (1.24 시리즈는 Py3.11까지 공식 지원).
- 향후 YOLO `ultralytics` 도입 예정 — ultralytics는 `numpy<2` 요구.
- 최신 langchain / openai / 기타 ML 라이브러리는 numpy>=2 끌어옴 → `pip install` 순서에 따라 silent 업그레이드 → ultralytics import 런타임 실패.

**Decision**:
- **핀 버전**: `numpy==1.26.4` (Py3.12 + ultralytics 양쪽 검증된 최신 1.x).
- **적용 위치**: 모든 `pip install` 단계의 **마지막**에 `pip install "numpy<2" --upgrade --force-reinstall` 1회.
- **검증**: 재핀 후 `python -c "import numpy, ultralytics; assert numpy.__version__.startswith('1.')"` 실행.
- **install 순서 원칙**: ultralytics를 먼저 설치 → 그 다음 langchain/openai → 마지막에 numpy 재핀. langchain이 numpy>=2 끌어오는지 catch.

**Consequences**:
- numpy 2.x를 요구하는 신규 라이브러리 도입 시 ultralytics 사용과 양립 불가 → 도입 차단 또는 ultralytics 대체 평가 필요.
- numpy 1.26.4 EOL 도래 시 ADR 갱신 + COMPATIBILITY 매트릭스 동시 갱신.
- `--force-reinstall`은 pip 캐시 무효화 비용 발생 → installer 끝단에 1회만 수행 (Hard Rule #2 idempotency 준수 — 재실행 시 동일 결과).
- ultralytics가 numpy 2.x를 공식 지원하는 시점 (upstream issue 추적 필요) 에 본 ADR 재검토.

---

### ADR-003: Phase 2 진입 전 사전 검증 — 외부 의존성 4건 결과

**Date**: 2026-05-26

**Context**: `MIGRATION_NOTES.md` § 7 에서 식별된 4건의 외부 의존성 (humble 환경에는 존재하지만 jazzy / Noble 환경에선 별도 검증이 필요한 항목). 1건이라도 부재면 Phase 2 설계 변경 필요. Phase 2-1 착수 전 모두 확인 완료.

**Decision**: **4건 전부 활성. Phase 2 GO**, 설계 변경 없음.

| # | 의존성 | 검증 결과 | Source |
|---|--------|-----------|--------|
| 1 | doosan-robot2 upstream `jazzy` 브랜치/태그 | **존재** | 사용자 확인 |
| 2 | NVIDIA CUDA Noble (`ubuntu2404`) repo | **활성** (HTTP 200) | `curl -fsI https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/` — `cuda-keyring_1.1-1_all.deb` 제공 |
| 3 | librealsense2 Noble apt repo | **지원** | 사용자 확인 |
| 4 | ROS2 Jazzy Noble apt packages | **활성** (HTTP 200) | `curl -fsI http://packages.ros.org/ros2/ubuntu/dists/noble/main/binary-amd64/Packages.gz` — `ros-jazzy-{rclpy,xacro,control-msgs,realsense2-camera-msgs}` 등 확인 |

**Consequences**:
- Phase 2 전체 task (2-1 ~ 2-14) 를 ROADMAP 그대로 진행. 보류/우회 없음.
- **NVIDIA CUDA 설치 방식 modernize 후보**: 현재 humble installer 는 `cuda-repo-ubuntu2204-12-4-local_*.deb` (약 1.4GB local installer) 를 wget + dpkg + `cp keyring`. NVIDIA Noble 측은 `cuda-keyring_1.1-1_all.deb` (소형 keyring 전용 패키지) 를 표준으로 제공. Phase 2-6 에서 local installer 방식 → keyring + 일반 `apt install cuda-toolkit-12-X` 방식으로 전환 검토. 다운로드 1.4GB → 수십 KB, idempotency 향상.
- 본 검증은 **시점 의존적**. NVIDIA / OSRF / Doosan 측 정책 변경 시 재검증 필요. Phase 2 작업 도중 `apt-get install` 실패 등이 발생하면 본 ADR 의 검증을 재실행 후 ADR-004 로 결과 갱신.
- CUDA 12.4 가 Noble 에서 동작하는지 (단순히 repo 활성 ≠ 모든 toolkit 버전 호환) 는 Phase 2-6 실제 설치 시 확인. Noble 공식 지원 toolkit 버전을 사전 조사 후 핀 결정 권장.

---

### ADR-004: PEP 668 대응 — venv (`--system-site-packages`) + `~/.bashrc` 자동 source

**Status**: ⚠️ **Superseded by ADR-008 (2026-05-27)** — Phase 4 (yolo/voice 컨테이너화) 결정 후 host venv 의 책임이 사라짐. application Python 은 모두 컨테이너로. 본 ADR 의 결정은 더 이상 적용되지 않음. 아래 내용은 결정 흐름 추적을 위해 보존.

**Date**: 2026-05-26

**Context**:
- Ubuntu 24.04 (Noble) 의 system Python 은 `/usr/lib/python3.12/EXTERNALLY-MANAGED` 파일로 `pip install` 차단 (PEP 668).
- humble 시절 본 레포는 venv 없이 system Python 에 직접 `pip install` (예: `a06-Voice.sh` 의 `pip install langchain openai ...`, `numpy --force-reinstall`).
- jazzy 환경에서 그대로 실행하면 `error: externally-managed-environment` 로 모든 pip 단계 실패.
- ROS2 jazzy 의 `rclpy`, `launch`, `ament-*`, `realsense2-camera-msgs` 등 python bindings 는 apt 가 `/opt/ros/jazzy/lib/python3.12/site-packages` 에 배치. venv 가 이를 못 보면 모든 ROS2 노드의 import 깨짐.

**Decision**:
- **venv 사용**, `python3 -m venv --system-site-packages ~/cobot_ws/.venv` 로 생성.
  - `--system-site-packages` 가 핵심: system 의 `/opt/ros/jazzy/lib/...` 와 `/usr/lib/python3/dist-packages` 를 venv 안에서도 import 가능.
  - 위치 `~/cobot_ws/.venv` — 기존 ROS2 워크스페이스와 동일 위치 (`~/cobot_ws/src/` 와 형제). venv 와 워크스페이스 lifecycle 일치.
- **자동 activate**: `~/.bashrc` 에 idempotent guard 와 함께 ROS2 setup + venv activate 한 묶음 추가. 새 터미널 열면 즉시 사용 가능.
- **순서 (`~/.bashrc` 안)**:
  1. `source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash` — system ROS2 우선
  2. `source ~/cobot_ws/.venv/bin/activate` — venv 가 사용자 패키지 layer 추가
- 모든 후속 `pip install` (a02, a04, a06, resources/python-dependency.sh, resources/cuda-pytorch-install.sh) 은 venv 가 active 한 상태에서 실행 → 자동으로 venv 대상.
- numpy 재핀 (ADR-002) 도 venv 안에서 수행 → system numpy (ROS2 가 의존) 안 건드림.

**Consequences**:
- **시스템 안전성**: ROS2 jazzy 가 의존하는 system numpy / scipy 등을 pip 가 덮어쓸 위험 0. apt 와 pip 의 영역이 깔끔히 분리.
- **재현성**: `~/cobot_ws/.venv` 를 통째로 삭제하면 깨끗한 재시작 가능. system 은 영향 없음.
- **`--break-system-packages` 옵션 거부 이유**: 빠르지만 system Python 패키지를 silently 덮어써 ROS2 의 rclpy import 가 segfault 또는 import error 로 깨질 위험. 사후 디버깅 비용 > venv 도입 비용.
- **`EXTERNALLY-MANAGED` 파일 삭제 옵션 거부 이유**: PEP 668 도입 취지 (system Python 보호) 를 정면으로 무시. Hard Rule #9 (비가역 state-changing) 영역에 진입. Python 3.13+ 업그레이드 시마다 재실행 필요.
- **`uv venv` 옵션 거부 이유**: 재현성은 더 좋으나 uv 자체가 신규 의존성 (Rust 바이너리). 본 레포는 ROS2 / Doosan 통합 환경 학습자 대상 — 표준 `python3 -m venv` 가 학습 곡선과 호환성 양면에서 유리. uv 는 순수 Python 데이터/ML 프로젝트 (예: RL_study) 에 적합.
- **`~/.bashrc` 자동 source 의 부작용**: 사용자가 기존에 다른 venv / conda 환경을 쓰고 있으면 충돌 가능. idempotent guard (`grep -q '# ROKEY ROS2 + venv'`) 로 중복 추가는 막지만, 첫 추가 시 사용자에게 명시적 confirm prompt 필요 (Hard Rule #9).
- **non-interactive 셸 케이스**: `~/.bashrc` 는 interactive 셸에서만 source 됨. CI / cron / systemd 에서 venv 가 필요하다면 별도 wrapper (`resources/activate.sh`) 도 동시 제공 — Phase 2-2 작업 시 함께 생성.
- **검증 명령** (Phase 2 종료 시):
  ```bash
  bash -ic 'python3 -c "import rclpy, torch, numpy, ultralytics, cv2; print(numpy.__version__, torch.cuda.is_available())"'
  # rclpy: system, torch/numpy/ultralytics/cv2: venv → 모두 OK, numpy 1.26.x, torch CUDA True 기대
  ```
- **Hard Rule #6 (Reproducibility) 강화**: venv 위치를 `~/cobot_ws/.venv` 로 고정함으로써 다른 머신에서 동일 경로 재현 가능. `pip freeze > ~/cobot_ws/.venv/requirements.lock.txt` 단계를 Phase 2-10 끝단에 추가 권장 (lock 파일은 venv 안에만 두고, git 관련 처리 없음 — ADR-005).
- **venv 생성 위치 (Phase 2-2b) 확정**: `a02` 첫 단계. 이유: `a01` 은 NVIDIA driver 설치 + `sudo reboot` 으로 끝나서 venv 를 만들어도 `~/.bashrc` 자동 source 가 재부팅 후 다음 셸부터 적용 — 그 시점엔 다시 `a02` 진입이라 의미 중복. `a02` 시작부에서 만들면 같은 셸에서 즉시 `source` 후 후속 pip 단계 모두 venv 안에서 동작.

> **Superseded note (2026-05-27)**: 위 모든 결정은 Phase 4 컨테이너화로 무효화됨. host venv 자체가 폐기 — `python3-venv` 설치 / `~/.bashrc` 자동 source / lock 파일 / activate wrapper 모두 미적용. 자세한 흐름은 ADR-008.

---

### ADR-005: 본 레포는 GitHub publish 의도 없음 — git artifact 관련 결정 비활성화

**Date**: 2026-05-26

**Context**:
- 사용자 명시: "github 에 올리는 용도가 아니기 때문에 git 관련해서는 관여 x".
- 본 레포는 로컬 워크스테이션 셋업 도구. 작성자/사용자 1인이 자기 머신에서 사용. 원격 remote push, 외부 협업, PR 워크플로 의도 없음.
- 그동안 발생한 git 관련 후보 결정: `.gitignore` 신규 항목 (`*.zip`, lock 파일 등), `requirements.lock.txt` 커밋 여부, commit 메시지 컨벤션, Co-Authored-By 정책.

**Decision**:
- **본 레포에서 git artifact 관련 모든 결정은 보류 / 비활성화**.
- 구체적으로:
  - `.gitignore` 신규 항목 추가 / 점검은 사용자가 명시적으로 요청할 때만 수행 — 자동 권유 금지.
  - `requirements.lock.txt`, 임시 산출물, 백업 zip 등 lock/output 파일의 추적 여부는 결정하지 않는다 (venv 안에 그대로 둠).
  - commit, branch, push, PR 관련 행동은 모두 사용자 명시적 요청 시에만.
  - 기존 `.gitignore` 와 `CLAUDE.md` 의 "Commit only when explicitly requested" 정책은 유지 — 무해.
- Hard Rule #11 ("No AI attribution in git artifacts") 의 운영적 의미: **본 레포에 적용될 일이 없음** (git artifact 자체를 만들지 않으므로). 단 룰 자체는 CLAUDE.md 에 남겨둠 — 향후 다른 레포에서 fork / 재활용 시를 위한 safeguard.

**Consequences**:
- 향후 AI 가 "이 파일은 `.gitignore` 에 추가하는 게 좋겠습니다" 식의 자동 권유 금지. 메모리에도 동일 정책 반영.
- 산출물 파일 (예: `Installfile_2026_A_v2.zip`, `requirements.lock.txt`, install log) 의 추적 여부 논의는 모두 skip — 사용자가 직접 결정.
- `MIGRATION_NOTES.md § 10` ("비-소재 파일, `.gitignore` 에 `*.zip` 추가 권장") 의 권장 사항도 보류. 사용자 별도 요청 시까지 보류.
- 본 ADR 은 사용자가 publish 의도를 명시적으로 바꾸면 (예: "이거 깃허브에 올릴 거야") 즉시 무효화 — 그 시점에 `.gitignore` / commit 정책 재검토 ADR 새로 작성.

---

### ADR-006: CUDA 메이저 버전 = 12-8 (cu128), host 미설치 — Phase 4 컨테이너 적용

**Date**: 2026-05-29

**Status**: ✅ 확정

**Context**:
- humble baseline 은 host 에 CUDA 12.4 toolkit (apt) + PyTorch 2.6.0+cu124 (pip) 를 설치했다 (`backup/cuda-pytorch-install.sh`).
- Noble (24.04) NVIDIA cuda repo 에는 **12-4 가 부재** — 가용 메이저는 12-5/12-6/12-8/12-9/13-0/13-1/13-2 (ADR-003 검증). 따라서 humble 의 12.4 를 그대로 못 가져옴 → 메이저 재결정 필요.
- 설치된 NVIDIA 드라이버 595.71.05 (a01 실측) 는 CUDA 13.x 까지 지원 → 드라이버는 12.x/13.x 모두 만족, 제약이 아님.
- 진짜 제약은 **PyTorch wheel 가용성**: PyTorch 안정판 Linux pip wheel 은 `cu118 / cu126 / cu128` 만 제공하며 **`cu130` (CUDA 13.x) wheel 은 없음** (pytorch.org/get-started 실측 2026-05-29). PyTorch 를 쓰는 한 13.x 는 선택 불가.
- ADR-008 (host venv 폐기) 로 application Python (PyTorch / ultralytics / cv2) 의 home 이 host → Phase 4 컨테이너로 이동. host colcon 빌드 패키지 (robot_control / od_msg / doosan-robot2) 중 CUDA 를 import 하는 것은 없다.

**Decision**:
- **CUDA 메이저 = 12-8 (PyTorch `cu128`)**. 12-6 대비 더 최신 안정 라인 — 향후 GPU/기능 커버리지와 호환성 여유. 12-6 도 가용하나 12-8 채택 (사용자 결정 2026-05-29).
- **host 에는 CUDA toolkit / PyTorch 를 설치하지 않는다**. host 에 CUDA 소비자가 없고 (cobot2_ws host 패키지는 CUDA 무관), 컨테이너의 PyTorch wheel 은 자체 CUDA 런타임을 번들하고 host 의 **드라이버**만 nvidia-container-toolkit 경유로 사용한다. host CUDA toolkit 은 dead weight.
- **CUDA 12-8 + PyTorch cu128 은 Phase 4 yolo 컨테이너 base image 에서만** 설치/핀. numpy<2 재핀 (ADR-002) 도 그 Dockerfile 마지막 layer.
- M3 (a02) 의 CUDA/PyTorch host 설치 단계 (humble 의 `cuda-pytorch-install.sh`) 는 **마이그레이션하지 않고 폐기** — Phase 4 로 이관.

**Consequences**:
- **M3 unblock**: ADR-006 대기로 막혀 있던 a02 가 CUDA 무관 작업 (DSR + RealSense) 으로 재정의되어 즉시 진행 가능.
- `resources/config.sh` 의 `CUDA_VERSION` 은 host 설치에 쓰이지 않음 — Phase 4 Dockerfile 이 참조할 값 (`12-8`) 으로 의미가 바뀜. host 스크립트에서 이 변수를 읽는 코드 없음.
- **검증 기준 (ADR-008 정합)**: host `python3 -c "import torch"` → ImportError 가 의도된 정상 결과. `torch.cuda.is_available()` 은 컨테이너 안에서만 True.
- COMPATIBILITY.md 의 CUDA/PyTorch 행을 "host 미설치 / Phase 4 컨테이너 / 12-8·cu128" 로 갱신.

**Reopen 조건**:
- PyTorch 가 cu130 wheel 을 정식 제공하기 시작하고 13.x 의 이점이 분명해지면 재검토.
- host 에서 직접 CUDA 연산 (컨테이너 밖 nvcc 빌드) 이 필요한 패키지가 등장하면 host toolkit 설치 재검토.
- ultralytics 가 요구하는 PyTorch 최소 버전이 cu128 비호환으로 바뀌면 메이저 재결정.

---

### ADR-007: Docker image publish & secret hygiene — Phase 4 컨테이너 배포 전략

**Date**: 2026-05-27

**Context**:
- Phase 4 가 yolo-detection / voice-processing 을 컨테이너로 분리. 두 image 모두 동일 RTX 4060 Laptop 환경에서만 사용 — 한 번 build 성공 시 환경 변화 없으면 안정적. 빌드 비용 큼 (CUDA + PyTorch + ultralytics = 5–10GB / 수 분~수십 분).
- 사용자 명시 (2026-05-27): 외부 코드 유출 우려 없음 (본 레포는 환경설정 installer, 외부 가치 있는 내부 코드 없음).
- 유일 차단 요인: voice-processing 의 `OPENAI_API_KEY` 가 image layer 에 박히면 public registry 노출이 비가역.
- ADR-005 (GitHub publish 의도 없음) 는 git artifact 한정 — Docker Hub publish 는 별개 결정.

**Decision**:

1. **Publish 매체**: **Docker Hub public** 채택. Free tier 의 무제한 public repo 활용. 사용자 코드 leak 무관, secret hygiene 만 준수.

2. **Image tag 정책 (Hard Rule #6 강화)**:
   - `latest` 태그 **금지** (silent drift 차단).
   - 1차 권장: semantic version (`v0.1.0`, `v0.2.0`, …) — 의도된 release 시점에만 bump.
   - 2차 권장: git short SHA (7 char) — 코드와 image 의 1:1 mapping.
   - 동일 image 에 두 태그 동시 부착 가능 (`ros2-jazzy-yolo:v0.1.0` + `:abc1234`).

3. **Publish target naming**:
   - `docker.io/<DOCKERHUB_USER>/ros2-jazzy-yolo:<tag>`
   - `docker.io/<DOCKERHUB_USER>/ros2-jazzy-voice:<tag>`
   - `DOCKERHUB_USER` 환경변수 — Phase 4 진입 시 `.env.example` 에 placeholder 추가, 빌드/publish 스크립트는 `${DOCKERHUB_USER:?missing}` 패턴.

4. **Secret hygiene (Hard Rule #10 강화) — 3중 차단**:
   - **`.dockerignore`** 에 `.env`, `.env.*`, `*.key`, `*.pem`, `secrets/`, `.git/` 명시.
   - **build-time secret 주입 금지** — `ARG`/`ENV` 로 API key 안 받음 (`docker history` 평문 노출). **runtime env injection 만** 사용 (`docker-compose.yml` 의 `environment:` 가 host `.env` 참조, image 자체엔 placeholder 도 안 박힘).
   - **multi-stage build** — 빌드 임시 파일 / pip cache / 자격증명이 final stage 에 미잔존.
   - **publish 전 mandatory 검증** (CI 없음 → 사용자 수동):
     ```bash
     docker history --no-trunc <image>:<tag> | grep -iE 'OPENAI|API_KEY|TOKEN|SECRET'
     # match 1건이라도 발견 시 publish 차단 + image 재빌드
     ```

5. **install.sh (M5) pull-first 분기**:
   ```bash
   if docker manifest inspect "${DOCKERHUB_USER}/ros2-jazzy-yolo:${YOLO_TAG}" >/dev/null 2>&1; then
       docker compose pull
   else
       docker compose build --pull
   fi
   docker compose up -d
   ```
   본 분기의 최종 형태는 Phase 4 base image / network 결정 (별도 ADR 예정) 과 묶여 확정.

**Consequences**:
- **빌드 시간 절약**: 신규 노트북 셋업 시 yolo + voice 빌드 단계 (수 분~수십 분) 스킵 → `docker compose pull` 통팩.
- **재현성 향상**: 모든 노트북이 동일 SHA256 digest image 사용 — layer-level 재현성.
- **secret hygiene 검증이 publish workflow mandatory step (Hard Rule #10)**: CI 없으므로 사용자 수동 책임. 1회 leak 시 PAT revoke + 모든 의존처 갱신 + image 삭제 (외부 mirror cache 보존 위험 잔존).
- **`DOCKERHUB_USER` / `DOCKERHUB_TOKEN` 환경변수 신규**: Phase 4 진입 시 `.env.example` 에 placeholder 추가. Docker Hub PAT (personal access token) 사용 권장 — 평문 password 입력 금지.
- **publish workflow (push 자체) 미정**: 수동 `docker push` vs Makefile target vs 별도 release 스크립트 — Phase 4 진입 시 결정.
- **Free tier rate limit**: anonymous 100/6h, authenticated 200/6h pull. 본 레포 사용자 ~5 노트북 이하 예상 → 실질적 제약 없음.
- **ADR-005 와의 관계 명시**: GitHub publish 의도 없음 ≠ Docker Hub publish 의도 없음. 본 ADR 가 후자만 명시적으로 허용 (코드 leak 위험 0 인 환경설정 도구이기 때문).

**Reopen 조건**:
- secret hygiene 수동 검증이 1회 fail (image 안에 key 박힘 발견) → pre-push hook / CI 자동화 도입 검토.
- Docker Hub pull rate limit 에 실제로 부딪힘 → GHCR private / 로컬 mirror 로 분기.
- 다른 GPU 환경 (RTX 4060 외) 추가 도입 시 image 의 CUDA arch (sm_89) 호환성 재검증 필요.

---

### ADR-008: host venv 폐기 — application Python 은 컨테이너 안에만 (ADR-004 supersede)

**Date**: 2026-05-27

**Context**:
- ADR-004 (2026-05-26) 결정 시점엔 Phase 4 (yolo + voice 컨테이너화) 가 ROADMAP 에 없었다. 당시 시나리오는 humble 시절 `a06-Voice.sh` 가 host system Python 에 직접 설치하던 application Python 패키지 (langchain, openai, numpy, ultralytics, cv2, …) 를 jazzy 의 PEP 668 제약 하에서 어떻게 처리할지였고, 답이 venv 였다.
- 2026-05-27 사용자가 Phase 4 신설 — yolo 와 voice 가 각각 Docker container 로 분리. application Python 패키지의 진짜 home 이 host venv 가 아닌 컨테이너 image 안으로 이동.
- 사용자 질문 (2026-05-27): "host PC 에 venv 가 왜 필요해? 거기에는 어떤 게 깔리는 거야?" — Phase 4 이후 host venv 가 담을 게 거의 없다는 점이 드러남.

**Decision**:
- **host venv 폐기**. `~/cobot_ws/.venv` 생성 / `~/.bashrc` 자동 source / `activate.sh` venv 라인 / `venv-bootstrap.sh` 헬퍼 / `requirements.lock.txt` — 모두 미적용.
- host 영역의 Python 책임을 다음으로 한정:
  - **system Python (apt 영역)**: ROS2 `rclpy` / `launch` / `colcon` / `ament-*` — `/opt/ros/jazzy/lib/python3.12/site-packages` 와 `/usr/lib/python3/dist-packages`. host 가 직접 `pip install` 하지 않음.
  - **colcon 워크스페이스**: `~/cobot_ws/install/` — `doosan-robot2` 등 ROS2 패키지 빌드 산출물.
- application Python (PyTorch / ultralytics / langchain / openai / cv2 / PyAudio / openwakeword 등) 은 **모두 컨테이너 image 안**에서만 존재.
- PEP 668 우회 불필요 — host 에서 `pip install` 자체를 안 함.

**Consequences (구조 변경 영향)**:
- **ADR-004 supersede**: ADR-004 의 결정 사항 (venv 생성, bashrc 자동 source, lock 파일) 모두 무효.
- **ADR-002 (numpy<2 핀) 의 적용 위치 변경**: host venv 끝단 → 각 컨테이너의 Dockerfile 마지막 layer. 의도와 install 순서 원칙은 그대로 (ultralytics → langchain → numpy 마지막 재핀).
- **M1 헬퍼 정리**:
  - `resources/venv-bootstrap.sh` **삭제**.
  - `resources/activate.sh` 의 venv source 라인 제거 — ROS2 source 만 남김.
  - `resources/config.sh` 의 `VENV_PATH` 변수 제거.
- **ROADMAP Phase 2 정리**:
  - 2-2b (venv 도입) **삭제**.
  - 2-1 의 `VENV_PATH` 변수 정의 제거.
  - 2-10 의 `a06-Voice.sh` 마이그레이션 — host 에서 pip install 단계 자체 제거. a06 의 역할이 거의 없어짐 (`.env` placeholder 와 OpenAI key 로드 패턴만 남길지 별도 결정 — Phase 4 에서 voice 컨테이너가 .env 를 mount 하므로 host a06 자체가 무의미).
  - 2-3 의 pip/setuptools/wheel upgrade — host 에서 안 함. 각 컨테이너 Dockerfile 의 RUN 단계로 이동.
- **MIGRATION_NOTES § 9, 14, 15, 16 reframing**: host pip pin / pip 도구 노후 / PyTorch wheel 메이저 일치 — 모두 컨테이너 빌드 컨텍스트로 이동. host 영역의 의미는 사라짐.
- **host 개발자 편의 손실**: host 에서 `python3 -c "import numpy"` 같은 빠른 smoke test 불가. 컨테이너 진입 (`docker exec`) 필요. 수용 가능한 trade-off — 본 레포의 본질이 production 환경 셋업이지 host 개발 환경 셋업 아님.
- **재현성 향상**: application Python 의 진실 소스가 Dockerfile 1곳. host 환경 오염 없음.

**검증** (Phase 2 / Phase 4 종료 시):
- host: `which python3` → `/usr/bin/python3` (system, venv 없음)
- host: `python3 -c "import rclpy"` → OK (system bindings)
- host: `python3 -c "import torch"` → ImportError (의도된 결과 — torch 는 컨테이너 안에만)
- container: `docker exec rokey-yolo python3 -c "import torch; assert torch.cuda.is_available()"` → OK

**Reopen 조건**:
- host 에서 직접 Python 개발 / debugging 빈도가 잦아 컨테이너 진입 비용이 의미 있게 커지면 host venv 재도입 검토.
- 또는 컨테이너에서 못 다루는 라이브러리 (예: 특정 ROS2 노드 안에서 application Python 직접 사용) 가 등장하면 재검토.

---

### ADR-010: 로컬 git 도입 — rollback / bisect 안전망, 외부 publish 의도 없음

**Date**: 2026-05-27

**Context**:
- 본 레포는 ROS2 Humble installer → ROS2 Jazzy installer 로의 distro 마이그레이션 작업 중. 작업의 본질이 **diff** (humble 상태 vs jazzy 상태). 마이그레이션 도중 의도와 다른 동작이 발생하면 직전 작동본으로 회귀할 수단이 필요.
- ADR-005 (2026-05-26) 가 GitHub publish 의도 부재를 명시. 그 결정의 의도는 외부 공개 / 협업 / PR 워크플로 차단이었지 **로컬 버전 관리** 차단이 아님.
- 사용자 명시 (2026-05-27): "잘못되었을 경우를 대비한 rollback 을 위해서 git init 하고 상태 관리정도는 하면 좋겠다."

**Decision**:

1. **로컬 git repository 도입**. `git init` 후 본 레포 디렉토리에서 git 운영 시작.

2. **remote 추가 금지**. `git remote add` 명령으로 remote 등록 안 함 (`git remote -v` 결과 = 빈 출력 유지). push 사고 예방.

3. **commit 메시지 정책 — 외부 친화 (사용자 결정 2026-05-27)**:
   - 본 레포가 미래에 외부로 공개될 가능성을 0 으로 가정하지 않음. commit history 는 외부 사람이 읽어도 이해 가능하게.
   - **내부 축약어 / 단계 라벨 금지**: 내부 마일스톤 코드 (M1, M2 등), 본 레포 내부 결정 기록 번호 (ADR-NNN), "Hard Rule #N" 같은 룰 ID, "Phase N" 같은 단계 번호.
   - **기능 단위 분할**: 한 commit = 한 논리 변경 (예: "humble 시절 installer 보존을 위한 backup 디렉토리 분리" / "재시작 가능한 설치 진행 추적 헬퍼 추가"). 여러 무관 변경을 한 commit 에 묶지 않음.
   - **언어**: 한국어 회화 + 영어 식별자 혼용.
   - **AI attribution 금지** (기존 정책 유지): `Co-Authored-By`, "Generated with X" footer 어떤 형태로도 추가 안 함.

4. **branch 정책**:
   - 기본 branch = `main`.
   - 단발성 실험 / 위험한 변경은 short-lived feature branch (`migrate-system-layer`, `try-cuda-12-8` 등) 에서 시도 후 fast-forward merge.
   - long-lived branch (`dev`, `release` 등) 운영 안 함 — 단일 사용자 + 외부 협업 의도 없음.

5. **tag 정책 — 외부 친화**:
   - milestone 도달 시 semver tag (`v0.1.0`, `v0.2.0`, …) 부착. 외부 사람이 봐도 "버전" 으로 인식 가능.
   - tag annotation 에 기능 요약 (예: `v0.2.0 — 시스템 레이어 설치 스크립트 jazzy 마이그레이션 완료`). 내부 단계 코드 제외.
   - tag 자체에 내부 축약어 (`M2-complete`, `phase-2-system-layer` 등) 미사용.

6. **commit timing**:
   - AI 자동 commit 금지 (기존 정책 유지).
   - 사용자가 명시적으로 요청할 때만 commit 생성.
   - destructive 작업 (apt purge, rm -rf, NVIDIA driver 교체 등) 직전 사용자 판단으로 안전망 commit 권장.

7. **secret leak 방지** (기존 정책 강화):
   - `.gitignore` 에 `.env`, `.env.*` (단 `.env.example` 은 추적) 명시.
   - 모든 commit 직전 `git status` / `git diff --cached` 로 staged 파일 검토. 자격증명 의심 파일이 staged 되면 즉시 unstage.

**Consequences**:
- **rollback 가능**: `git reset --hard <sha>`, `git revert`, `git checkout -- <file>` 로 직전 작동본 복구. 마이그레이션 작업의 안전망.
- **bisect 가능**: 의도와 다른 동작 발생 시 `git bisect` 로 깨진 commit 정확히 추적. 14 단계 마이그레이션 작업에서 가치 큼.
- **diff 활용**: humble 시절 (`backup/`) 과 마이그레이션 후 (`resources/`) 의 diff 를 git 차원에서 비교. 시간축 history 보존.
- **ADR-005 scope 명시화**: ADR-005 는 **외부 publish** 의도 차단 한정. 로컬 git 운영 / 로컬 commit / 로컬 tag 는 본 결정으로 허용. 두 결정은 직교.
- **외부 공개 대비**: commit/tag 메시지가 외부 친화로 작성되어 있어 미래에 publish 의도를 바꾸더라도 history 재작성 불필요.
- **운영 비용**: commit 작성 / staging 검토 시간 추가. 단 distro 마이그레이션 작업의 회귀 비용 (한 단계 처음부터 재실행 = 10분 이상) 대비 무시 가능.

**Reopen 조건**:
- 사용자가 외부 publish 의도를 명시적으로 결정 시 → branch / tag / commit 정책 재검토.
- secret leak 사고 발생 시 → `.gitignore` 정책 강화 + pre-commit hook 도입 검토.
- 단일 사용자 가정이 무너져 협업이 시작되면 → branch / PR 정책 추가 결정 기록 작성.

---

### ADR-011: 단일 진입점 install.sh 통합 + run_step 중앙화 (2026-05-29)

**Context**:
- host 시리즈 a01~a04 가 jazzy 패턴으로 정리됐으나 진입점이 4개로 분산 → "한 번에 워크스테이션 셋업" 진입점 부재.
- `run_step` 함수가 4개 오케스트레이터에 동일 본문으로 중복 정의(분모 변수명 `A0N_STEPS` 만 차이) → 수정 시 4곳 동기화 부담.
- state 파일은 이미 단일 경로(`~/.ros2_jazzy_test/state`)를 공유하고 step 이름이 `a01_`/`a02_` 등으로 네임스페이스됨 → 통합의 전제가 이미 충족.

**Decision**:
- **구조 A 채택**: 기존 a01~a04 는 "개별 스테이지 재실행용"으로 유지하고, 전체를 단일 연속 시퀀스(`[n/11]`)로 실행하는 `install.sh` 를 신규 추가. 두 경로가 같은 state 파일을 공유하므로 어느 쪽으로 실행하든 완료 step 은 자동 skip(재시작 가능 규칙 고수).
- **run_step 중앙화**: 중복된 `run_step` 을 `resources/run-step.sh` 로 분리. 진행률 분모는 호출 시점에 `STEPS_TOTAL`(미설정 시 config 의 `TOTAL_STEPS`) 을 읽어 통합/단독 실행 모두 대응. state 마킹/조회는 state.sh 가 전담(책임 분리).
- **reboot 경계**: a01 마지막 reboot 단계는 `run_step` 으로 감싸지 않고 install.sh 에 인라인. reboot 전에 완료를 디스크에 기록해 재부팅 후 재실행이 그 단계를 건너뛰고 다음부터 이어가게 함(무한 루프 방지).
- **강건성 표준 세트**: preflight(OS codename 일치 + sudo 가용 확인) + ERR trap(실패 위치 보강) + `--status` / `--reset` / `--help`. 스테이지 선택 플래그(`--only`/`--from`)는 개별 스크립트 직접 실행과 기능이 겹쳐 보류.

**Consequences**:
- 신규 노트북 셋업이 `bash install.sh` 한 줄로 시작(완료분 skip, reboot 후 재실행으로 자연 이어짐).
- `run_step` 수정이 한 파일로 수렴. 오케스트레이터는 `STEPS_TOTAL` 값만 설정.
- 진입점이 5개(install.sh + a0N 4개)로 늘지만, 권장 진입점을 install.sh 로 문서에 명시해 혼란 해소.
- 단계 추가 시 install.sh step 테이블과 config 의 `TOTAL_STEPS` 동시 갱신 필요(진행률 분모 일관성).

**Reopen 조건**:
- 스테이지 선택 실행 요구가 반복되면 → `--only`/`--from` 플래그 추가 재검토.
- 단계 수가 크게 늘어 install.sh step 테이블이 비대해지면 → 스테이지 메타데이터 테이블 기반 루프로 리팩터 검토.

---

### ADR-012: private 원격 저장소 1개 허용 — 타 머신 설치 검증 (2026-05-29, 외부 publish 금지 결정 부분 변경)

**Context**:
- 기존 결정은 "외부 publish 의도 없음 + remote 추가 금지" 로 원격 저장소 자체를 차단했다(로컬 git 만 운영).
- 동일 모델의 다른 노트북에서 installer 를 end-to-end 로 검증할 필요가 생김 → 코드를 옮길 경로가 필요. 로컬 전용 운영으로는 충족 불가.

**Decision**:
- **private 원격 저장소 1개 허용**. 본인 계정에서만 clone. public 전환은 금지 — 설치 스크립트에 추적 secret 은 없으나 공개는 비가역(캐시/인덱싱).
- push 안전장치: (1) push 전 secret 패턴 스캔, (2) `.gitignore` 로 세션 기록(`.jsonl`)·migration 작업 데이터·별도 튜토리얼 제외, (3) `.env` 미추적 확인(`.env.example` 템플릿만 추적).
- 타 머신 검증 전제로 `cobot2_ws/`(설치 단계가 symlink 소스로 의존) 와 컨테이너 템플릿을 추적 대상에 포함.
- 신규 remote 추가나 public 전환은 사용자 명시 동의를 다시 받는다.

**Consequences**:
- 외부 publish 를 일반 허용하는 것이 아니라, 검증용 private 경로 1개만 여는 좁은 변경. 협업/PR 워크플로는 여전히 도입하지 않음.
- 커밋/태그 메시지의 외부 친화 작성 규칙은 그대로 유효(미래 공개 가능성 대비).

**Reopen 조건**:
- 검증이 끝나 원격이 불필요해지면 → 저장소 삭제 + 로컬 전용 복귀 검토.
- secret leak 사고 시 → `.gitignore` 강화 + pre-commit hook 도입.
- 외부 공개나 협업이 실제로 필요해지면 → public 전환 / branch·PR 정책을 별도 결정으로 기록.

---

### ADR-009: Phase 4 컨테이너 base image / 네트워크 모드 / 빌드 게이트 분리 (2026-05-30)

**Context**:
- Phase 4 진입 전 미해결이던 세 결정(base image / ROS2 네트워크 모드 / install.sh 통합)을 확정해야 컨테이너 Dockerfile 작성이 가능.
- 사용자 결정(2026-05-30): "실 검증(host e2e) 전에 컨테이너 이미지 생성 단계를 먼저 만들고 개별 검증." 의존성 매핑 결과, 컨테이너 작업은 (A) 빌드+isolated import (host 콘텐츠 의존 0) 와 (B) host 노드와의 통합(host 의존) 으로 갈린다.
- `cobot2_ws` 의 일부 패키지가 빌드 차단 버그 보유: voice `setup.py` 가 없는 `resource/.env` 참조, object_detection/voice_processing `package.xml` 에 런타임 의존 미선언(최소 ros-base 이미지에서 cv_bridge/std_srvs 미해소).

**Decision**:
- **Base image = `ros:jazzy-ros-base-noble` 단일** (yolo/voice 공통, named 태그 핀). yolo 도 `nvidia/cuda` base 안 씀 — PyTorch cu128 wheel 이 CUDA 런타임 라이브러리를 자체 번들하고, GPU 는 런타임에 `nvidia-container-toolkit` 가 host driver 를 주입한다. OS 에 CUDA toolkit 불필요(이미지 비대화 회피). `template/Dockerfile` 의 `ubuntu:24.04` self-build 패턴은 상속하지 않고, `entrypoint` source 패턴 + `SHELL` fail-fast 만 계승.
- **네트워크 모드 = `network_mode: host`** (ROADMAP 4-4 후보 a). host `robot_control`(client) ↔ 컨테이너 service(server) 의 DDS discovery 자연 동작. 보안 격리보다 ~5 노트북 단순성 우선.
- **CUDA_VERSION = 12.8** 을 `resources/config.sh` 에 주입(`:=12.8`). 유일 소비자는 yolo Dockerfile build-arg (host 미사용). pip index 는 `cu${CUDA_VERSION//./}` = cu128.
- **소스 수정 정책**: object_detection/voice_processing 의 빌드 차단 버그는 `cobot2_ws` 소스에서 직접 수정(host colcon 미빌드 → host 영향 0). **`od_msg` 는 원본 보존** — host `robot_control` 과 공유하는 type hash 단일 소스라, yolo Dockerfile 에서 `rosidl-default-generators` 툴체인 apt 설치로만 우회(host 재빌드/hash 재정합 불필요).
- **빌드 게이트 ↔ acceptance 경계**: "개별 검증" = 이미지 빌드 + 컨테이너 내부 import smoke + secret 위생까지. GPU 런타임(`torch.cuda.is_available()`), service 왕복, od_msg type hash 정합은 host e2e(Phase 3) 이후 단계 — 빌드 게이트 통과를 Phase 4 PASS 로 격상하지 않는다(lessons L-004/L-007: 정적·import 통과 ≠ 동작).
- **빌드 도구**: 타깃 머신에 docker compose 플러그인 부재 → `containers/build-all.sh` 는 `docker build` 직접 사용(엔진만 필요). `docker-compose.yml` 은 런타임(up) 단계용으로 보존, install.sh 자동 호출 안 함(ADR-007/ROADMAP 4-6 책임 분리 유지).

**Consequences**:
- yolo/voice 가 동일 base layer 공유 → pull/디스크 효율. multi-stage(builder→runtime) 로 build-essential/pip cache 를 최종 이미지에서 제거.
- 컨테이너 빌드를 host e2e 와 병행/선행 가능 → reboot 포함 host 사이클을 기다리지 않고 host 무관 결함(voice `.env` 참조, package.xml 의존, tflite-runtime wheel 가용성 등)을 조기 노출.
- `od_msg` 미수정으로 host robot_control 영향 0 — 단 type hash 정합은 빌드 게이트에서 검증 불가(구조적으로 동일 소스 COPY 까지만 보장), host 통합 단계로 이월.

**Reopen 조건**:
- 다중 노트북 동시 운용으로 ROS_DOMAIN_ID 충돌이 생기면 → `network_mode: host` 대신 bridge + 도메인 격리(4-4 후보 b) 재검토.
- yolo 이미지에 nvidia/cuda base 가 실제로 필요한 상황(예: 특정 CUDA 라이브러리 OS 의존)이 드러나면 → base 재선택.
- od_msg 인터페이스가 변경되면 → host/yolo 동시 재빌드 + hash 재정합 절차를 통합 단계 ADR 로 기록.

---

### ADR-013: NVIDIA 드라이버 closed 핀 + HWE 커널 트랙 고정 + modules-extra 보장 (2026-06-01)

**Date**: 2026-06-01

**Context**:
- 타 노트북(동일 모델)에서 `install.sh` 클린 설치 중, NVIDIA 단계 직후 재부팅에서 **검은 화면 + 깜빡이는 `_` 로 부팅 정지** 발생.
- 추적 결과 단일 원인이 아니라 `nvidia-driver-install.sh` 의 `ubuntu-drivers install` **자동 선택**에서 세 문제가 파생:
  1. 비결정적 드라이버 선택 — 머신/시점마다 다른 드라이버.
  2. 자동 선택된 드라이버가 HWE 커널 이미지를 의존성으로 끌어오지만 `linux-modules-extra-<kernel>`(wifi / 일부 USB 입력 드라이버)는 함께 오지 않음 → 그 커널로 부팅 시 wifi·USB 키보드 소실(노트북 실측: GA 6.8 커널로 부팅하면 정상, 반쪽 HWE 6.17 로 부팅하면 소실).
  3. 모듈 적재 실패가 재부팅 후 검은 화면으로만 드러남(설치 중 검증 없음 → silent brick).
- RealSense(`librealsense2-dkms`)도 동일 계열의 커널-헤더 결합을 가짐 — 커널 바뀌면 DKMS 재빌드가 헤더 없이는 실패.
- 작업 머신은 깨진 노트북과 같은 6.17 HWE 커널인데도 정상. 유일한 차이가 **HWE 메타(`linux-generic-hwe-24.04`) + `modules-extra` 존재**였다.

**Decision** (사용자 결정 2026-06-01 — installer 를 작업 머신 기준으로 고정):
1. **커널 트랙을 HWE 로 고정** — 새 step `kernel-baseline.sh`(a01 의 첫 단계)가 `linux-generic-hwe-24.04` + `linux-headers-generic-hwe-24.04` 메타를 `--install-recommends` 로 설치해 이미지 + 헤더 + `modules-extra` 를 함께 보장. nvidia/RealSense DKMS 보다 먼저 실행.
2. **NVIDIA 드라이버를 `nvidia-driver-595` (closed) 로 명시 핀** — `config.sh` 에 `NVIDIA_DRIVER_VERSION=595` / `NVIDIA_DRIVER_FLAVOR=""`. 자동선택 폐기(빈값 VERSION 일 때만 폴백). 커널-모듈 메타 `linux-modules-nvidia-595-generic-hwe-24.04` 동반 → 커널 업데이트 시 nvidia 모듈 자동 추적. 드라이버 userspace 만 hold(메타는 hold 안 함 — hold 하면 추적 끊김).
   - 변형 선택 경위: 처음엔 작업 머신과 동일하게 `-open` 으로 핀했으나, 동일 모델 노트북에서 `-open` + KMS 가 내장 패널 디스플레이를 못 올려 부팅 후 검은 화면(gdm 세션 실패)이 났다(nvidia 모듈 blacklist 로도 미해결 — 잔여 nvidia 디스플레이 설정 정황). closed 드라이버로 재설치하니 정상 부팅·디스플레이 확인되어 closed 를 기본으로 채택. open↔closed 는 커널 모듈만 다르고 userspace(CUDA 등)는 동일.
3. **재부팅 전 검증 게이트** — nvidia 설치 직후 부팅 예정 커널(설치된 최신 커널)에 `nvidia.ko` 가 실제로 있는지 확인, 없으면 `exit 1` 로 reboot 단계 진입 차단.
4. **RealSense 헤더 메타 의존** — `linux-headers-$(uname -r)` 단독 대신 `linux-headers-generic-hwe-24.04` 메타 동반(커널 업데이트 후 헤더 자동 추적).

**Consequences**:
- 동일 모델 타 머신에서 검증된 구성(6.17 HWE + nvidia-driver-595 closed + modules-extra)을 결정적으로 재현. 반쪽 커널 brick 과 비결정적 드라이버 선택이 제거됨.
- step 총수 11 → 12(신규 `a01_kernel_baseline`). state 키 이름 불변이라 resumability 유지.
- `docs/TROUBLESHOOTING.md` 신설 — 검은 화면 / 커널 모듈 누락 / 다중 커널 항목.

**Reopen 조건**:
- GA(6.8) 트랙이 필요한 하드웨어가 생기면 → 커널 트랙 변수(`KERNEL_META`)를 `linux-generic` 으로 전환하고 nvidia 모듈 메타 명명도 함께 조정.
- open 드라이버로 되돌릴 이유(예: closed 가 특정 GPU/커널에서 회귀, 또는 open 이 디스플레이 정상)가 드러나면 → `NVIDIA_DRIVER_FLAVOR=-open` 으로 전환.
- Secure Boot 활성 타깃이 생기면 → MOK 등록 단계를 별도 결정으로 추가.

---

### ADR-014: 배포 variant 브랜치 분기 (full host vs 컨테이너) + ADR-008 의 application-shell 한정 부분 환원

**Date**: 2026-06-02

**Context**:
- 실기(noble/Python 3.12) 검증에서 두 결함 발견.
  1. **host application Python 누락**: ADR-008 이 host pip 을 폐기하고 앱 Python 을 컨테이너로 옮겼는데, `dsr-project-install.sh` 가 host ws 로 복사하는 패키지도 `robot_control od_msg` 로 한정돼 있었다. 그 결과 host 에서 `ros2 run robot_control` 런타임에 `ModuleNotFoundError`(scipy/numpy/pymodbus) — ament_python 은 빌드시 import 하지 않아 colcon 빌드는 통과하지만 런타임에 깨진다. `pick_and_place_text/detection` 은 host 에서 ultralytics 를 직접 import 한다(토폴로지 검증).
  2. **openwakeword 가 Python 3.12 에서 미동작**: `wakeup_word.py` 가 `.tflite` 모델을 로드하는데, openwakeword 0.6.0 은 `tflite-runtime>=2.8` 을 의존으로 강제하고 tflite-runtime 은 Python 3.12 wheel 이 없다(최대 3.11).
- 사용자 결정(2026-06-02): 두 배포 방식을 **브랜치 variant** 로 분기. `feat/application-shell` = 컨테이너 없이 host 단독 실행(monolith), `feat/application-containers` = host 최소화 + yolo/voice 컨테이너(ADR-008/009 유지).

**Decision**:
- **브랜치 variant 분기**. 공통 코드(cobot2_ws / 셸 프레임워크)는 공유하되 host Python 설치 범위가 갈린다.
  - `application-shell`: `dsr-project-install.sh` 의 `HOST_PKGS` 를 host 실행 패키지 전체로 확장(robot_control / od_msg / pick_and_place_text / pick_and_place_voice / rokey / voice_processing / object_detection). 신규 `resources/host-python-deps.sh`(a02 step) 가 host venv 에 앱 Python 을 설치.
  - `application-containers`: `HOST_PKGS` 현행 유지, host 는 robot_control 용 thin client 만.
- **ADR-008 의 application-shell 한정 부분 환원**. ADR-008 의 Reopen 조건 #2("컨테이너에서 못 다루는 라이브러리 — 특정 ROS2 노드 안에서 application Python 직접 사용 — 가 등장하면 재검토")에 정확히 해당: robot_control(ROS2 노드)이 host 에서 scipy/pymodbus 를 직접 쓰고, application-shell 은 정의상 모든 노드를 host 실행한다. 따라서 application-shell 에서만 host venv(`--system-site-packages`)를 재도입한다. `application-containers` 는 ADR-008 그대로.
- **PEP 668(noble) 회피 = venv `--system-site-packages`** (system Python 전역 pip / `--break-system-packages` 비채택 — system rclpy 오염 회피, ADR-004 의 venv 논거 재사용). 핀은 Phase 4 컨테이너 Dockerfile(검증본)을 미러링(torch cu128 / ultralytics<9 / opencv-python<4.10 / langchain<2 / numpy<2 마지막 재핀).
- **venv↔`ros2 run` 연동**: colcon 빌드를 venv active 에서 수행(`colcon-build.sh`) → ament_python entry_point console_script 의 shebang 이 venv python 으로 박혀 `ros2 run` 이 venv 의 앱 Python 을 본다. (ADR-004 식 `~/.bashrc` 자동수정은 침습적이라 채택하지 않고, opt-in `resources/activate.sh` 가 ROS+overlay+venv 를 함께 켠다.)
- **openwakeword Python 3.12 해법 (컨테이너에서 실측 검증 완료)**: openwakeword `0.6.0` 을 `--no-deps` 로 설치(불가능한 tflite-runtime 의존 회피) + 실제 의존을 명시 설치하되 tflite-runtime 자리에 후속작 **ai-edge-litert**(cp312 wheel, 동일 `Interpreter` API)를 넣고, openwakeword 코드가 `import tflite_runtime.interpreter` 를 하드 호출하므로 `tflite_runtime → ai_edge_litert` 최소 shim 을 site-packages 에 생성한다. feature 모델(melspectrogram/embedding/VAD)은 wheel 미동봉이라 `download_models()` 로 받는다. **`.tflite` 모델·`wakeup_word.py` 코드는 그대로 유지**. 컨테이너(`voice-processing/Dockerfile`)와 host(`host-python-deps.sh`) 동일 레시피. 검증은 `import` 가 아닌 **`Model(.tflite)` 인스턴스화 + predict** 로(빌드게이트 smoke 도 동일하게 강화).
- **pymodbus 2.x→3.x 코드 이관**: onrobot.py 3개(robot_control / pick_and_place_text / pick_and_place_voice)의 `pymodbus.client.sync` → `pymodbus.client`, `unit=` → `slave=`. 3.x 는 통신 실패 시 예외 대신 에러객체를 반환하므로 read·write 결과 모두에 `isError()` 가드 추가(cryptic AttributeError → fail-loud, gripper write 실패도 silent 진행 차단).

**Consequences**:
- step 총수 12 → 13(신규 `a02_host_python_deps`, colcon-build 직전). `config.sh` `TOTAL_STEPS`, `install.sh`/`a02` 분모 동시 갱신. state 키 `a02_host_python_deps` 추가(resumability 유지).
- ADR-008 의 검증 항목 "host `import torch` → ImportError(의도)" 는 **application-shell 에서 무효**(host venv 에 torch 존재). application-containers 에선 여전히 유효.
- ADR-002(numpy<2 재핀) 적용 위치가 application-shell 에선 host venv 끝단으로 환원.
- **gripper 안전(BLOCKING)**: pymodbus 3.x 이관은 SW 변경이라 import smoke 로는 register write 의미가 검증되지 않는다. 실 RG gripper open/close/move 하드웨어 재검증 없이 실로봇 운용 금지. 3.x minor 별 `slave` vs `device_id` 인자명도 실기에서 확인.
- 두 feature(공통 fix = pymodbus 3 파일 + voice Dockerfile openwakeword 레시피)는 두 브랜치에 동기화 필요.

**검증** (실기 noble/3.12):
- 컨테이너에서 선검증 완료: `Model(.tflite)` 로드 + predict OK(`tflite_runtime.interpreter.Interpreter` → `ai_edge_litert.interpreter`).
- host: `bash install.sh` ×2 멱등 / `ros2 run robot_control robot_control` 런타임 import OK / `${HOST_VENV}/bin/python -c "import numpy; assert numpy.__version__.startswith('1.')"` / `import torch` OK.

**Reopen 조건**:
- 두 variant 를 단일 브랜치로 통합 요구 / host venv 유지비용 과다 시.
- openwakeword 가 ai-edge-litert 를 정식 의존으로 채택한 릴리스가 나오면 shim 제거 검토.
- pymodbus 3.x minor API(`slave`→`device_id`)가 더 바뀌면 onrobot.py 재점검.

---

### ADR-015: 카메라 소유권 host 이전 — yolo 컨테이너는 토픽 subscribe (2026-06-02)

**Date**: 2026-06-02

**Context**:
- Notion 워크플로우 다이어그램 2-1-a(통신 구조 축약) 갱신으로 컨테이너 토폴로지 변경. 종전 설계(구현본)는 `realsense2_camera` 노드를 yolo 컨테이너 안에서 USB passthrough(`/dev/bus/usb`)로 실행했다(yolo Dockerfile runtime 의 `ros-jazzy-realsense2-camera`, compose 의 주석 USB devices).
- 사용자 결정(2026-06-02): 카메라를 **host 소유**로 이전. host 가 `realsense2_camera` 를 실행해 `/camera/camera/*` 를 publish 하고, yolo 컨테이너의 `object_detection` 노드는 그 토픽을 DDS 로 subscribe 만 한다.
- 근거: `object_detection.realsense.ImgNode` 는 이미 `/camera/camera/{color/image_raw, aligned_depth_to_color/image_raw, color/camera_info}` 의 **구독자**다(rclpy/sensor_msgs/cv_bridge 만 import — realsense2_camera 패키지 무의존). 카메라 드라이버를 컨테이너에 둘 구조적 이유가 없고, USB passthrough·udev·커널 모듈을 컨테이너로 끌고 가는 함정을 host 책임으로 되돌리면 단순해진다. host 는 이미 `realsense-ros-install.sh`(a02)가 `ros-jazzy-realsense2-camera` 설치.

**Decision**:
- **yolo 컨테이너에서 카메라 드라이버 제거**: `containers/yolo-detection/Dockerfile` runtime 스테이지의 `ros-${ROS_DISTRO}-realsense2-camera` apt 제거. `cv-bridge`/`sensor-msgs` 는 구독·변환에 필수라 유지. builder 스테이지 무변경.
- **USB passthrough 제거**: `docker-compose.yml` yolo 서비스의 주석 USB `devices` 블록 삭제(카메라가 host 라 불필요). `network_mode: host` 는 유지 — 이제 host↔컨테이너 service 왕복뿐 아니라 **카메라 토픽 구독**도 이 경로로 일어난다.
- **host 카메라 기동은 운영 절차**: 컨테이너 up 전에 host 에서 `ros2 launch realsense2_camera rs_launch.py align_depth.enable:=true`. `align_depth` 누락 시 `aligned_depth_to_color` 미publish → 노드 depth 계산 실패(TROUBLESHOOTING 카탈로그 + compose 헤더에 명시).
- **RMW 일관성 명시 핀**: host↔컨테이너가 같은 topic/service 를 보려면 RMW 일치 필요. `config.sh` 가 `RMW_IMPLEMENTATION`(기본 `rmw_fastrtps_cpp`=jazzy 기본 — **ADR-016 에서 `rmw_cyclonedds_cpp` 로 변경됨**)을 export(host 는 activate.sh 경유), compose 두 서비스도 동일 기본값 참조. `ROS_DOMAIN_ID` 와 함께 양쪽 동일해야 discovery 성립.

**Consequences**:
- yolo 이미지에서 realsense2_camera + 그 transitive 의존 제거 → 이미지 약간 축소. ADR-009 의 base/네트워크/빌드게이트 결정은 그대로 유효 — 본 ADR 은 카메라 배치만 변경(ADR-009 의 컨테이너-내 카메라 실행 가정을 대체).
- 빌드게이트(`build-all.sh`) 영향 없음 — yolo smoke 는 `object_detection.realsense` import(구독자, realsense2_camera 무의존)라 제거 후에도 PASS.
- 운영 의존 추가: 컨테이너만 띄우면 안 되고 host 카메라 노드가 선행해야 함(host/application 2-step 에 카메라 기동 1줄 추가).
- application-shell 변형은 무관(전부 host 실행이라 카메라도 자연히 host). 본 변경은 application-containers 한정.
- Notion 2-1 풀 다이어그램 / 3-1 스택 / 3-2-4 는 아직 카메라-in-컨테이너 표기 → 문서 정합 필요(코드가 단일 진실, 2-1-a 기준).

**Reopen 조건**:
- 카메라를 다시 컨테이너로 넣을 구조적 이유(예: 다중 카메라를 컨테이너별 격리)가 생기면 → USB passthrough + udev 책임 재설계.
- RMW 를 CycloneDDS 로 표준 변경 시 → config.sh 기본값 + 양쪽 일관성 재점검. (→ ADR-016 에서 실행)

---

### ADR-016: RMW 표준 = CycloneDDS + 대용량 토픽 커널/소켓 버퍼 + 유선 NIC whitelist 자동화 (2026-06-05)

**Date**: 2026-06-05

**Context**:
- RealSense raw 토픽(color 1프레임 ≈ 2.6MB, depth/pointcloud)을 안정적으로 수신·측정하려는 과정에서 RMW/버퍼 함정 3종이 드러났다.
  1. fastrtps + `ros2 topic hz`(rclpy 단일 스레드)는 대용량 메시지 역직렬화가 publish 를 못 따라가 실제 30fps 여도 15Hz 안팎으로 출렁(측정 artifact). 같은 콜백의 작은 토픽(`camera_info`)은 29.98Hz 안정 → 카메라/노드는 정상.
  2. CycloneDDS 로 바꾸면 UDP fragment 재조립 버퍼(`net.core.rmem_max` 기본 ~208KB)가 한 프레임보다 작아 대용량 토픽이 전량 유실(0Hz).
  3. CycloneDDS `SocketSendBufferSize` 는 하드 최소값이라 커널 `wmem_max` 가 요청치(64MB)보다 작으면 도메인 생성을 거부하고 노드가 SIGABRT.
- 커널 sysctl 버퍼 + CycloneDDS XML 버퍼를 함께 올리고, DDS 가 wifi 대신 유선 NIC 만 쓰게 인터페이스를 화이트리스트하니 raw 토픽이 30Hz(camera_info 와 일치)로 복원됐다(실측 검증, 본 머신).
- 그러나 이 해결책이 전부 일회성 수동 작업이라 (1) 타 머신/재설치 재현 불가, (2) NIC 이름이 머신·포트마다 달라 XML 하드코딩이 깨짐, (3) Phase 4 컨테이너가 fastrtps 기본이라 host(cyclonedds)와 discovery 불가.
- 사용자 결정(2026-06-05): RMW 표준을 CycloneDDS 로 전환하고 설치 단계에서 NIC·버퍼를 자동 구성.

**Decision**:
- **RMW 표준 = `rmw_cyclonedds_cpp`**. `resources/config.sh` 기본값을 fastrtps → cyclonedds 로 변경(ADR-015 의 "기본 fastrtps" 핀을 supersede). `CYCLONEDDS_XML`/`CYCLONEDDS_URI`/`DDS_NETIF`/`ROS_DOMAIN_ID`(단일 소스, 기본 42) 를 config.sh 에 추가.
- **커널 버퍼 영속**: `resources/sysctl-cyclonedds.conf` → `/etc/sysctl.d/60-cyclonedds.conf`. rmem/wmem max·default, ipfrag_time/high/low_thresh, netdev_max_backlog. sysctl 과 XML 은 **세트로 배포**(XML 만 있으면 wmem 부족으로 노드 사망).
- **유선 NIC whitelist 자동화**: `resources/cyclonedds.xml.in` 템플릿 + `resources/dds-tuning.sh` 가 설치 머신의 물리 유선 NIC 를 carrier 무관하게 전부 탐지(무선/docker/가상 제외)해 `<NetworkInterface presence_required="false"/>` 로 렌더. 로봇 미연결 설치·로봇 포트 변경 모두 견고하고, 목록에 wifi 가 없어 무선 fallback 이 원천 차단된다. `DDS_NETIF` 로 override 가능.
- **설치 통합**: `install.sh` step 13(`dds_tuning`)로 추가, `STEPS_TOTAL`/`TOTAL_STEPS` 12→13. 단독 실행(`bash resources/dds-tuning.sh`)도 지원(하드웨어 변경 시 재생성).
- **컨테이너**: `network_mode: host`(ADR-009 유지) 덕분에 컨테이너가 host net namespace 를 공유 → 커널 sysctl 버퍼와 유선 NIC 를 그대로 상속. compose 가 RMW 기본을 cyclonedds 로 바꾸고 `CYCLONEDDS_URI` env + host 의 `cyclonedds.xml` read-only mount 만 추가하면 host↔컨테이너 discovery 성립(docker0 화이트리스트 불필요).

**Consequences**:
- host·컨테이너가 단일 cyclonedds 환경으로 통일, 대용량 토픽 30Hz 결정적 재현.
- 렌더된 `cyclonedds.xml` + `/etc/sysctl.d/60-cyclonedds.conf` 는 머신 종속 산출물 → 레포 추적 안 함(템플릿·스크립트만 추적). fleet 타 머신은 같은 installer 가 그 머신 NIC 를 자동 주입.
- 런타임 전제 추가: 로봇/카메라가 연결된 유선 포트가 up 이어야 cyclonedds 노드가 기동(presence_required=false 지만 전 포트 down 이면 사용가능 인터페이스 0 → 실패, 의도된 동작).
- COMPATIBILITY 매트릭스의 "기본 fastrtps" 서술을 본 결정이 supersede(cyclonedds 행 추가).
- **dsr-emulator(dev 전용 3rd-party 이미지)는 미변경** — 이미지가 cyclonedds rmw 를 안 가질 수 있어 RMW 강제 시 기동 실패 위험. dev 프로파일에서 에뮬레이터와 host 통신이 필요하면 그때 RMW 정합을 별도 점검(실기 우선이라 보류).

**Reopen 조건**:
- 멀티캐스트 차단망/특수 토폴로지에서 enp* 자동탐지가 부적합하면 → `DDS_NETIF` 명시 또는 subnet 기반 선택으로 재설계.
- dsr-emulator 와 cyclonedds 통신이 필요해지면 → 에뮬레이터 이미지 RMW 정합 결정.

---

### ADR-017: 애플리케이션 통신 토폴로지 = robot_control 중심 star(ROS2 service) 확정 + 통합 bringup launch (2026-06-05)

**Date**: 2026-06-05

**Context**:
- Phase 4 컨테이너 통합 중 "socket → ROS2 service 전환" 요청이 있었으나, `cobot2_ws` 애플리케이션 코드는 **이미 전부 ROS2 service 기반이고 socket 이 전혀 없음**을 확인. 현행 구조는 host 의 `robot_control`(DSR_ROBOT2) 이 오케스트레이터로서 `/get_keyword`(std_srvs/Trigger, voice 컨테이너) 와 `/get_3d_position`(od_msg/SrvDepthPosition, yolo 컨테이너) 를 **순차 호출하는 star**. voice·yolo 는 서로 직접 통신하지 않는다.
- Notion 워크플로우 문서 내부가 불일치: 상세도(2-1)는 robot_control 이 두 service 를 모두 호출하는 star(=코드 일치)인데, 간이도(2-1-a)는 `/get_keyword` 엣지를 yolo↔voice 로 그려 chain(voice→yolo 직접)처럼 보였다. 사용자가 간이도 구조를 의도했었다며 star 적합성을 질문.
- 검토 결과: chain(yolo 가 voice 를 호출)은 robot_control + object_detection + srv 계약 재작성을 요구하면서 기능 이득이 없고, 안전·시퀀스 제어를 모션 주체에서 떼어내며, yolo·voice 의 단일 책임을 깨 결합도를 높인다.

**Decision**:
- **통신 토폴로지 = star 유지(확정).** robot_control(host) 이 두 service 의 client. yolo("target→3D position")·voice("→keyword") 는 서로를 모르는 독립 service server. **통신 코드·service 계약·인터페이스 변경 없음.**
  - 근거: ① 안전·시퀀스 소유권을 실제 모션 주체(robot_control)에 집중 ② 단일 책임 디커플링(yolo·voice 단독 테스트/재사용 가능) ③ 멀티타깃 반복 루프가 이미 robot_control 에 존재 ④ ROS2 service 동기 req/resp 의미론이 "로봇이 묻고 서버가 답"하는 star 에 최적(forward chain 은 중첩 동기 호출로 블로킹) ⑤ chain 전환은 변경 비용만 들고 이득 0.
- 카메라 소유권은 본 결정에서 재결정하지 않음 — **카메라 host 소유 결정(2026-06-02)** 을 그대로 따른다(host realsense2_camera publish → yolo object_detection subscribe).
- **통합 bringup launch 도입**: `cobot2_ws/launch/bringup_all.launch.py` — 로봇 드라이버(dsr_bringup2) + host RealSense + yolo/voice 컨테이너(`docker compose up -d`)를 한 번에 기동. robot_control(실제 pick 모션 + 무한 루프)은 안전상 기본 제외(`start_robot_control:=true` 옵트인). `mode` 기본 `virtual`(에뮬레이터). 컨테이너 노드는 각 이미지 ENTRYPOINT(ROS source + colcon overlay) + CMD 로 자동 실행되므로 compose up 한 줄이 노드 기동까지 일으킨다.
- **문서 정합**: Notion 2-1-a 간이도의 `/get_keyword` 엣지를 yolo↔voice → **host↔voice** 로 정정(상세도·코드 일치). 2-1 상세도/3-1 스택의 카메라-in-컨테이너 표기 및 `docs/DEVELOPMENT_ROADMAP.md` Phase 4 의 동일 표기를 **host 소유**로 정정(2026-06-02 카메라 결정이 이미 명시한 "문서 정합 필요"의 후속).

**Consequences**:
- 노드/서비스 코드 무변경 — 산출물은 launch 파일 + 결정/로드맵/Notion 문서 정합뿐. 회귀 위험 최소.
- `bringup_all.launch.py` 는 ament 패키지 밖 standalone(절대경로 `ros2 launch`). 실행 셸은 `/opt/ros/jazzy/setup.bash` + `~/cobot2_ws/install/setup.bash`(overlay) + `resources/config.sh` 를 source 해야 한다(`activate.sh` 는 overlay 미source — 실행 전제로 안내). 후속 패키지화 시 `robot_control/launch/` 이동 + setup.py `data_files`.
- `containers:=true` 는 이미지 빌드·`.env`·`cyclonedds.xml` 렌더 선행 필요. 미빌드 상태 점검은 `containers:=false`.
- 실기 E2E(이미지 재빌드 후 service 왕복 + 카메라 토픽 컨테이너 가시성)는 후속 단계로 연기.

**Reopen 조건**:
- yolo·voice 가 중앙 오케스트레이터 없이 event-driven 자율 동작해야 할 요구가 생기면 → topic/action 기반 재설계 재검토.
