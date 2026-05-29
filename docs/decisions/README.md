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
