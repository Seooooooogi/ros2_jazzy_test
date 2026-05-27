# ros2_jazzy_test — Project Memory Index

> 본 파일은 글로벌 `SessionStart` hook이 자동 로드. 매 세션 시작 시 노출됨.
> 200줄 이후는 truncate — 인덱스만 유지하고 상세는 별도 파일에 둘 것.

## Identity (요약)
- **What**: ROS2 Humble installer → ROS2 Jazzy installer 마이그레이션. bash 셋업 스크립트 모음.
- **Stack**: Ubuntu 24.04 (noble) + ROS2 Jazzy + NVIDIA + Docker + CUDA + PyTorch + Doosan DSR + RealSense + Voice(LangChain/OpenAI).
- **Phase 진행 상태**: Phase 1 완료. ADR-003 검증 GO. Phase 2-1 (`resources/config.sh` 도입) 착수 대기.

## Hard Rules (CLAUDE.md 참조 — 절대 약화 금지)
1. ROS distro 단일 진실 소스 (`${ROS_DISTRO}`)
2. Idempotency 필수
3. Resumable installer (체크포인트)
4. 설치 진행률 시각화 `[n/total]`
5. `set -euo pipefail`
6. Docker 이미지 태그 핀 고정 (no `latest`)
7. apt repo 키링 일관성 (`/etc/apt/keyrings/`, no `apt-key add`)
8. 버전 호환 매트릭스 문서화 + transitive (numpy<2 for ultralytics)
9. State-changing 명령 명시적 confirm
10. No hardcoded secrets
11. No AI attribution in git artifacts

상세는 `CLAUDE.md` 본문. 글로벌 Tier 0와 일부 교집합 (#10 ↔ ai-constitution #5, #11 ↔ ai-constitution #11).

## Active Decisions
- **ADR-001**: 초기 스택 + Hard Rules 11개 (`docs/decisions/README.md`)
- **ADR-002**: numpy<2 핀 — ultralytics 호환 (`docs/decisions/README.md`)
- **ADR-003**: Phase 2 사전 검증 4건 모두 GO. NVIDIA CUDA Noble `cuda-keyring_1.1-1_all.deb` modernize 후보 (Phase 2-6).
- **ADR-004**: ~~PEP 668 venv~~ — **superseded by ADR-008** (2026-05-27). historical record.
- **ADR-005**: 본 레포는 **외부(GitHub) publish 의도 없음** — push / 외부 협업 / PR 워크플로 차단. 단 **로컬 git 운영은 별개 결정 (ADR-010 으로 허용)**. AI 가 외부 publish 관련 자동 권유 금지.
- **ADR-010 (2026-05-27)**: **로컬 git 도입** (rollback / bisect 안전망 목적). remote 추가 금지. commit 메시지 외부 친화 (내부 마일스톤 코드 / 결정 기록 번호 / 룰 ID 미사용, 기능 단위 분할). tag = semver. 기본 branch = `main`, 실험은 short-lived feature branch. 첫 baseline tag `v0.1.0` 부착 (2026-05-27).
- **ADR-007 (2026-05-27)**: Phase 4 컨테이너 (yolo / voice) 를 **Docker Hub public** 으로 publish. `latest` 금지 + semver/SHA 태그. Secret 차단 3중 layer (`.dockerignore` + runtime env injection only + multi-stage build) + publish 전 `docker history` grep 수동 검증 mandatory. `install.sh` (M5) 는 pull-first 분기 (`docker manifest inspect` 성공 시 `compose pull`, 실패 시 `compose build`).
- **ADR-008**: host venv 폐기. application Python (PyTorch / ultralytics / langchain / openai 등) 은 모두 Phase 4 yolo/voice 컨테이너 image 안에서만 존재. host 는 system Python (apt) + colcon 워크스페이스만 책임.

## 트러블슈팅 누적 (Phase 3 산출물 예고)
> 마이그레이션 중 발견하는 이슈는 `docs/TROUBLESHOOTING.md`에 카테고리별로. 본 인덱스에는 한 줄 요약만.

- (Phase 1-2 작업 중 채워질 예정)

## 외부 참조
- ROS2 Jazzy 공식 문서: https://docs.ros.org/en/jazzy/
- Ubuntu 24.04 (noble) ROS2 패키지: `https://packages.ros.org/ros2/ubuntu noble main`
- ultralytics numpy 제약: upstream issue 추적 필요 (numpy 2.x 지원 시점)
- **Humble 실측 검증본 (이정현, 2026-05-22, RTX 4060 Laptop)** — Phase 2 작업 시 "실제로 무엇이 설치되었는가" 의 진실 소스:
  - 시스템 요약: https://www.notion.so/teamsparkx/Rokey-2-Version-20260522-36c563918e59803cb719ca55e3e3369f
  - 전체 pip list: https://www.notion.so/teamsparkx/pip-list-Version-20260522-36c563918e5980c0af76f8b4332454fe
  - 핵심 발견: `apt upgrade -y` drift (NVIDIA 570→580, Docker 23→29), RealSense 22.04 공급 중단 → Noble 정식 복귀 예정, pip/setuptools/wheel 4년 노후

## 현재 세션 컨텍스트
- Phase 1 완료 + ADR-003 검증 GO + Notion 보고서 (https://www.notion.so/teamsparkx/36c563918e598000a563f72bdd3ba57c) 작성.
- 다음 행동: Phase 2-1 (`resources/config.sh` 단일 진실 소스). 자세한 진입점은 `session-handoff-LATEST.md`.
- 미완료 task: ROADMAP Phase 2 전체 (2-1 ~ 2-14), Phase 3.

## 도메인 사실 (Phase 2 작업 시 전제)
- 본 레포에 Dockerfile 없음 (host installer 범위). 외부 이미지 1개만 pull: `doosanrobot/dsr_emulator:3.0.1` (upstream `install_emulator.sh`, distro-agnostic). **Phase 4 (사용자 결정 2026-05-27) 에서 `containers/yolo-detection/Dockerfile` + `containers/voice-processing/Dockerfile` 신설 예정** — 독립 마이크로서비스 + ROS2 topic 공유 패턴.
- **Doosan Cobot 사용 모드 (2026-05-27)**: **실기 우선**. DSR emulator 는 받아두지만 거의 미사용 — docker-compose 의 `profiles: [dev]` 로 격리, 개발/테스트 시에만 명시적 활성화. DSR 제어 노드는 실기 (TCP/IP) 와 연결을 기본 가정.
- 글로벌 `ai-constitution.md` 는 RL_study 도메인 — 본 프로젝트(installer)엔 RL/notebook 룰 silent skip (무충돌).
- NVIDIA 가 Ubuntu 24.04 용 `cuda-keyring_1.1-1_all.deb` 표준 제공 → 1.4GB local installer 방식 modernize 가능 (Phase 2-6).
- **GitHub publish 의도 없음 (ADR-005)**: 본 레포는 로컬 셋업 도구. `.gitignore` 항목 추가, lock 파일 커밋, commit 메시지 등 git artifact 관련 모든 사항은 사용자 명시적 요청 시에만 처리. 자동 권유 금지.
- **host Python 책임 (ADR-008, 2026-05-27)**: host 에 venv 없음. application Python 패키지는 모두 Phase 4 컨테이너 image 안. host 는 system Python (apt 의 `python3-*`, `/opt/ros/jazzy/.../site-packages` 의 rclpy/launch/colcon) + colcon 워크스페이스 (`~/cobot_ws/install/`) 만 책임. host 에서 `pip install` 자체 안 함.
- **Voice 입력 소스 (2026-05-27)**: 노트북 내장 마이크. USB 외장 마이크 아님. voice-processing 컨테이너는 raw ALSA `/dev/snd` 가 아닌 PulseAudio/PipeWire socket mount (`${XDG_RUNTIME_DIR}/pulse`) 로 host audio 데몬 경유 — Ubuntu 24.04 기본 PipeWire 와 호환 + desktop mixer 충돌 회피.
- **호스트 환경 = RTX 4060 Laptop** (노션 검증본): 데스크탑이 아닌 노트북. battery / built-in mic / built-in speaker / USB 포트 제한 (RealSense USB 3.0 + 기타 device 공존) 같은 노트북 제약 고려 필요.
- **doosan-robot2 controller 통신 (2026-05-27 검증)**: host ↔ robot controller = **TCP socket port 12345 via DRFL** (Doosan Robot Framework Library, libpoco 의존). DDS 아님. DDS 는 ROS2 노드 간 통신만 — DSR_NODE 가 `/joint_states` publish, `/robot_command` subscribe. 즉 hardware ↔ DSR_NODE 는 TCP, DSR_NODE ↔ 다른 ROS2 노드는 DDS 두 layer.
- **Noble apt repo CUDA 가용 매트릭스 (2026-05-27 확인)**: `cuda-toolkit-{12-5, 12-6, 12-8, 12-9, 13-0, 13-1, 13-2}`. **12-4 부재** — humble 의 12.4 그대로 마이그레이션 불가. ADR-006 으로 메이저 결정 필요 (M3 진입 전).
- **레포 폴더 컨벤션 (2026-05-27 갱신)**: `resources/` = M1 신규 헬퍼 5종 (config / state / confirm / env-load / activate). `backup/` = humble 시절 8종 (참조용 보존). top-level `a01-a06.sh` = M2~M5 작업 중 갱신 대상, 현재 일시 깨진 상태.
- **레포 폴더 컨벤션 (2026-05-27 사용자 결정)**: `resources/` = jazzy 마이그레이션 작업 중인 신규/현행 스크립트만. `backup/` = humble 시절 원본 (참조용 보존). 둘 섞지 않음. Phase 1 산출물에서 `resources/humble-legacy/` 로 명명된 모든 자리도 `backup/` 으로 통일.
