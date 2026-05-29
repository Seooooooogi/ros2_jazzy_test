# ros2_jazzy_test v1.0

ROS2 Humble installer → ROS2 Jazzy installer 마이그레이션. Ubuntu + NVIDIA + Docker + ROS2 + CUDA + PyTorch + Doosan DSR + RealSense + Voice(LangChain) 환경을 워크스테이션에 일관되게 셋업하는 bash 스크립트 모음.

**Phase 4 추가 범위 (사용자 결정 2026-05-27)**: host 설치 후 yolo-detection 과 voice-processing 을 각각 Docker container 로 분리 운영 (독립 마이크로서비스 + ROS2 topic 공유). 본 레포의 Docker 사용 범위가 "host runtime + DSR 에뮬레이터 이미지 1개 pull" 에서 "+ 두 application 이미지 build/run" 으로 확장.

**host Python 책임 (ADR-008, 2026-05-27)**: host venv 폐기. application Python 패키지 (PyTorch / ultralytics / langchain / openai 등) 는 모두 Phase 4 컨테이너 안. host 는 system Python (apt, ROS2 bindings) + colcon 워크스페이스만 책임. host 에서 `pip install` 자체 안 함 → PEP 668 우회 불필요.

## Hard Rules (never bend)

1. **ROS distro 단일 진실 소스** — `humble` / `jazzy` 같은 distro 문자열을 스크립트마다 박지 않는다. 단일 환경변수 `ROS_DISTRO` 또는 `resources/config.sh` 같은 공통 파일에서 1회 정의하고 모든 스크립트가 참조. 다음 distro 마이그레이션 (jazzy → kilted/lyrical) 때 같은 작업을 반복하지 않기 위한 안전장치.

2. **Idempotency 필수** — 같은 스크립트를 N회 실행해도 결과가 동일해야 한다. apt source list 중복 추가, keyring 중복 등록, `pip install` 중복 패키지 설치 금지. 모든 destructive 작업 (`rm`, `apt purge`, `sources.list` 덮어쓰기)은 사전 존재 여부 체크 후 수행.

3. **Resumable installer (체크포인트)** — 설치가 중간에 실패하면 어디까지 성공했는지 기록 (`~/.ros2_jazzy_test/state` 또는 동급). 재실행 시 마지막 성공 단계 다음부터 `[n+1/total]`로 진행. 첫 단계부터 다시 시작 금지.

4. **설치 진행률 시각화** — 모든 설치 단계는 `[n/total] <step name>` 형식으로 stdout에 명시. 사용자는 항상 "지금 어디인지, 얼마나 남았는지"를 알 수 있어야 한다. 진행률 없는 silent 실행 금지.

5. **`set -euo pipefail` 필수** — 모든 `.sh` 파일 최상단 (shebang 다음). 중간 명령 실패 시 silent continue로 의존성 누락 상태로 다음 단계 진입하는 cascading failure를 차단.

6. **Docker 이미지 태그 핀 고정** — `FROM ros:latest` 또는 무태그 금지. `FROM ros:jazzy-ros-base-noble` 처럼 명시 태그만 사용. `docker pull` 시에도 태그 생략 금지. `latest`는 시간에 따라 silently drift 한다.

7. **apt repo 키링 일관성** — 새 외부 repo 추가 시 `/etc/apt/keyrings/<vendor>.{gpg,pgp}` 경로와 `signed-by=/etc/apt/keyrings/...` 명시. `apt-key add` 사용 금지 (deprecated, Ubuntu 22.04+에서 경고). 동일 vendor 키링은 1개 경로로 통일.

8. **버전 호환 매트릭스 문서화** — Ubuntu / ROS distro / CUDA / PyTorch / DSR / RealSense SDK / Python 버전을 `docs/COMPATIBILITY.md` 한 곳에 기록. 어떤 스크립트라도 버전을 임의 변경하면 매트릭스 갱신을 강제. 매트릭스 없이 버전 올리면 어떤 조합이 검증되었는지 추적 불가.
   - **Transitive dependency 함정**: 핀 필요 라이브러리는 transitive도 매트릭스에 명시. 특히 **`numpy<2`** — YOLO `ultralytics`가 numpy<2를 요구하지만 대부분 최신 라이브러리는 numpy>=2를 끌어옴. `pip install` 순서에 따라 silent 업그레이드 발생 → ultralytics import 시점 런타임 실패. 모든 Python venv 셋업 마지막에 `numpy<2` 재핀 + import 검증 필수.

9. **State-changing 명령은 명시적 confirm** — `sudo reboot`, `apt purge`, NVIDIA 드라이버 교체, Docker 데몬 재시작처럼 되돌릴 수 없는 작업은 사용자 confirm prompt 없이 자동 실행 금지. 진행 중 작업 / unsaved state 손실 방지.

10. **No hardcoded secrets** — OpenAI / Anthropic API key, GitHub PAT 등 자격증명은 스크립트에 절대 박지 않는다. `.env` 또는 사용자 환경변수에서 로드. `.env`는 절대 커밋 금지 (`.env.example`이 템플릿).

11. **No AI attribution in git artifacts** — commit message, PR description, AUTHORS / CONTRIBUTORS 자리에 Claude / Copilot / GPT / 기타 AI assistant를 `Co-Authored-By`, contributor, "Generated with X" footer로 추가하지 않는다. Commit / PR은 사용자 명의로만. git history는 비가역이라 amend / force-push 같은 destructive 복구가 필요해진다.

## Quick Ref

- Entry: `bash a01-prerequirements.sh` (첫 단계 — NVIDIA + Docker + ROS2 설치 후 reboot)
- 순차 실행: `a01 → reboot → a02 → a03 → a06` (RealSense 는 a02 단계에 흡수됨; humble 원본 a04/a05 는 `backup/` 보존)
- 정적 검증: `shellcheck *.sh resources/*.sh`
- Compatibility matrix: `docs/COMPATIBILITY.md` (Phase 1 산출물)
- 트러블슈팅 카탈로그: `docs/TROUBLESHOOTING.md` (Phase 3 산출물)
- ROADMAP: `docs/DEVELOPMENT_ROADMAP.md`
- ADR: `docs/decisions/README.md`

## Secrets Policy

- `.env` 절대 읽기 / 출력 / 로그 금지 — 환경변수로만 접근.
- `.env` 절대 커밋 금지 — `.env.example`이 placeholder 템플릿 (실제 값 없음).
- 신규 API key → `.env.example`에 placeholder 추가 + 스크립트는 `${VAR_NAME:?missing}` 패턴으로 로드.

## Dev Conventions

- 스크립트 작성 후 `shellcheck` 통과 없이 머지 금지.
- 새 단계 추가 시 `total` 카운트와 진행률 표시 동시 갱신 (Hard Rule #4).
- 새 외부 repo / Docker image 도입 시 `docs/COMPATIBILITY.md` 매트릭스 갱신 (Hard Rule #8).
- 로그는 append-only (`>> install.log`), 덮어쓰기 (`> install.log`) 금지.
- 커밋은 한 논리 변경 단위로 분리 (예: "RealSense distro 패치"와 "DSR 의존성 갱신"은 다른 커밋).
- 커밋은 사용자 명시적 요청 시에만 (Hard Rule #11).
- **커밋 메시지는 외부 사람이 이해 가능하게 작성** — 내부 마일스톤 코드 (M1, M2), 결정 기록 번호 (ADR-NNN), 단계 번호 (Phase N), 룰 ID (Hard Rule #N) 같은 본 레포 내부 축약어 미사용. 기능 단위로 분할. 한국어 회화 + 영어 식별자 혼용.
- **remote 추가 금지** — 본 레포는 로컬 git 운영만 (`git remote -v` 결과 = 빈 출력 유지). push 사고 예방.
- destructive 작업 (apt purge, rm -rf, NVIDIA driver 교체 등) 직전 사용자 판단으로 안전망 commit 권장.
- milestone tag 는 semver (`v0.1.0`, `v0.2.0`) — 외부 친화. 내부 단계 코드 (`M2-complete` 등) 미사용.
- humble → jazzy 마이그레이션 중에는 humble 스크립트를 **삭제하지 않고** `backup/` 같은 별도 경로로 보존 — Phase 3 트러블슈팅 카탈로그 작성 시 diff 참조용.

## Compact Instructions

컨텍스트 압축 시 다음을 우선 보존:
1. Hard Rules 전체 (11개)
2. 현재 작업 중인 Phase (ROADMAP 어느 단계)
3. 미완료 task와 그 상태
4. 진행 중 버그 / 오류 (특히 jazzy 호환성 이슈)
5. Dev Conventions
6. 본 세션에서 수정한 파일 경로
7. `docs/COMPATIBILITY.md`와 `docs/TROUBLESHOOTING.md`의 최근 갱신 항목
