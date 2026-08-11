# cobot2_jazzy_installer v1.0

ROS2 Humble installer → ROS2 Jazzy installer 마이그레이션. Ubuntu + NVIDIA + Docker + ROS2 + CUDA + PyTorch + Doosan DSR + RealSense + Voice(LangChain) 환경을 워크스테이션에 일관되게 셋업하는 bash 스크립트 모음.

**Phase 4 추가 범위 (사용자 결정 2026-05-27)**: host 설치 후 yolo-detection 과 voice-processing 을 각각 Docker container 로 분리 운영 (독립 마이크로서비스 + ROS2 topic 공유). 본 레포의 Docker 사용 범위가 "host runtime + DSR 에뮬레이터 이미지 1개 pull" 에서 "+ 두 application 이미지 build/run" 으로 확장.

**host Python 책임 (ADR-008, 2026-05-27)**: host venv 폐기. application Python 패키지 (PyTorch / ultralytics / langchain / openai 등) 는 모두 Phase 4 컨테이너 안. host 는 system Python (apt, ROS2 bindings) + colcon 워크스페이스만 책임. host 에서 `pip install` 자체 안 함 → PEP 668 우회 불필요.

**cobot2 외부화 (사용자 결정 2026-06-24)**: cobot2 애플리케이션 소스는 이 레포에서 제공하지 않는다(추적 제외). 레포 = **base 환경 인스톨러**(`install.sh`, 9 step) + **애플리케이션 셋업**(`setup-app.sh` — 워크스페이스 + 컨테이너). cobot2 는 사용자가 `~/cobot2_ws/src/cobot2` 에 직접 배치(취득 방식은 추후 git clone/fetch 로 교체 예정 — `setup-app.sh::obtain_cobot2` 단일 함수로 격리). corecode 튜토리얼도 레포 미포함 — 사용자가 `~/corecode` 에 배치(ADR-029 = corecode git 제거. install.sh 의 step 10 배치 verify 는 폐기 — 튜토리얼 전용 아티팩트라 base 설치가 확인하지 않음). OPENAI key 는 인스톨러가 다루지 않음 — voice_processing 노드가 자기 패키지 `resource/.env`(colcon 빌드 내장)를 load_dotenv 로 읽으므로, 사용자가 별도 안내에 따라 그 위치에 직접 배치(ADR-028 의 `~/.config/cobot2/.env` 이관은 폐기, 2026-07-10).

**bringup 진입점 이관 (2026-07-21)**: 통합 실행 진입점이 `cobot2_bringup/bringup_all.launch.py` → `m0609_rg2_bringup/bringup.launch.py` 로 바뀌었다(`containers/bringup.sh` 마지막 줄). `m0609_rg2_bringup` 은 이 레포도 cobot2 도 아닌 **별도 레포**(`M0609_REPO_URL` = https://github.com/ROKEY-SPARK/m0609_rg2_integration)의 패키지 — cobot2 와 같은 외부화 원칙을 따른다. 레포 본체는 `M0609_REPO_DIR`(기본 `~/m0609_rg2_integration`)에 clone 되고(이미 있으면 건드리지 않음 — 개발 중 작업본 보호, 이때 `M0609_REF` 무시), 워크스페이스에는 레포 전체가 아니라 `src/m0609_rg2_bringup` 패키지 하나만 `${DSR_WORKSPACE}/src` 로 **심볼릭 링크**된다(같은 레포의 `m0609_rg2_moveit` 은 moveit 스택을 통째로 끌어와 제외. colcon 이 심볼릭 링크 패키지를 인식하는 것은 실측 확인). 외부 의존 `onrobot-ros2` 는 `ONROBOT_COMMIT` SHA 로 핀 고정해 clone. 새 launch 인자: `mode`(virtual|real, 기본 virtual) / `host` / `port` / `rt_host` / `camera`(기본 false, **`mode` 와 무관** — 2026-07-22 에 `mode:=real` 의 카메라 강제 기동을 제거했다. 실기에서 카메라만 따로 띄우는 절차가 막히고 `camera:=false` 가 조용히 무시되던 문제) / `rviz`. 구 `gui` 인자는 없다(upstream 에서 무효였음). **카메라 토픽 계약은 바뀌었다** — 중복 namespace 를 없애 `/camera/camera/*` → **`/camera/*`**(launch 에서 `namespace='camera'` 제거, `name='camera'` 만 유지). 소비자(yolo `object_detection`, `pick_and_place_text` / `pick_and_place_voice` 의 `realsense.py::ImgNode`)는 `/camera/color/image_raw`, `/camera/aligned_depth_to_color/image_raw`, `/camera/color/camera_info` 를 **절대 경로**로 구독한다(2026-07-22 변경 — 상대 이름 + `-r img_node:__ns:=/camera` remap 방식은 폐기. 기동 지점 5곳에 흩어진 remap 인자를 한 곳만 빠뜨려도 노드가 정상 기동한 채 토픽만 조용히 비어, 실제로 컨테이너 수동 기동 문서에서 그 사고가 났다). 절대 이름은 네임스페이스 remap 의 영향을 받지 않으므로 구 remap 인자를 그대로 줘도 동작이 같다 — `containers/bringup.sh` 는 구 소스가 깔린 머신을 위해 전환기 동안 인자를 유지한다. TF 프레임 이름은 별개 파라미터(`camera_name`, 기본 `camera`)에서 나오므로 무변경(URDF 도 무변경). 단 소비자 소스 `~/cobot2_ws/src/cobot2` 는 어떤 git 레포도 추적하지 않아 이 패치가 타 머신에 전달될 보장이 없다 — 프로듀서만 갱신되면 파이프라인이 죽는다. DSR 서비스 경로(`/dsr01/dsr_controller2/...`), `/dsr01/joint_states`, TF 프레임 이름도 무변경. 새로 생기는 것은 URDF 의 RG2 그리퍼 + RealSense 브라켓 + D435, virtual 모드의 가상 그리퍼 노드(`/onrobot/sendCommand` 서비스 + `/onrobot_joint_states`). virtual 기동은 실측 검증, **실 로봇(`mode:=real`) / 실 RealSense / 실 RG2 는 하드웨어가 없어 미검증**.

## Hard Rules (never bend)

1. **ROS distro 단일 진실 소스** — `humble` / `jazzy` 같은 distro 문자열을 스크립트마다 박지 않는다. 단일 환경변수 `ROS_DISTRO` 또는 `resources/config.sh` 같은 공통 파일에서 1회 정의하고 모든 스크립트가 참조. 다음 distro 마이그레이션 (jazzy → kilted/lyrical) 때 같은 작업을 반복하지 않기 위한 안전장치.

2. **Idempotency 필수** — 같은 스크립트를 N회 실행해도 결과가 동일해야 한다. apt source list 중복 추가, keyring 중복 등록, `pip install` 중복 패키지 설치 금지. 모든 destructive 작업 (`rm`, `apt purge`, `sources.list` 덮어쓰기)은 사전 존재 여부 체크 후 수행.

3. **Resumable installer (체크포인트)** — 설치가 중간에 실패하면 어디까지 성공했는지 기록 (`~/.cobot2_jazzy_installer/state` 또는 동급). 재실행 시 마지막 성공 단계 다음부터 `[n+1/total]`로 진행. 첫 단계부터 다시 시작 금지.

4. **설치 진행률 시각화** — 모든 설치 단계는 `[n/total] <step name>` 형식으로 stdout에 명시. 사용자는 항상 "지금 어디인지, 얼마나 남았는지"를 알 수 있어야 한다. 진행률 없는 silent 실행 금지.

5. **`set -euo pipefail` 필수 (실행 진입점 `.sh`)** — 직접 실행되는 `.sh`(`install.sh` / `setup-app.sh` / `resources/{base-install,app-install,hostcfg}.sh`)는 최상단(shebang 다음)에 `set -euo pipefail`. 중간 명령 실패 시 silent continue로 의존성 누락 상태로 다음 단계 진입하는 cascading failure를 차단. **예외: source 전용 라이브러리**(`resources/{config,lib,activate}.sh`)는 `set -e` 를 두지 않는다 — sourced 파일의 `set -e` 는 호출자 셸 옵션을 오염시키므로, 셸 옵션은 호출 진입점이 소유한다.

6. **Docker 이미지 태그 핀 고정** — `FROM ros:latest` 또는 무태그 금지. `FROM ros:jazzy-ros-base-noble` 처럼 명시 태그만 사용. `docker pull` 시에도 태그 생략 금지. `latest`는 시간에 따라 silently drift 한다.

7. **apt repo 키링 일관성** — 새 외부 repo 추가 시 `/etc/apt/keyrings/<vendor>.{gpg,pgp}` 경로와 `signed-by=/etc/apt/keyrings/...` 명시. `apt-key add` 사용 금지 (deprecated, Ubuntu 22.04+에서 경고). 동일 vendor 키링은 1개 경로로 통일.

8. **버전 호환 매트릭스 문서화** — Ubuntu / ROS distro / CUDA / PyTorch / DSR / RealSense SDK / Python 버전을 `docs/COMPATIBILITY.md` 한 곳에 기록. 어떤 스크립트라도 버전을 임의 변경하면 매트릭스 갱신을 강제. 매트릭스 없이 버전 올리면 어떤 조합이 검증되었는지 추적 불가.
   - **Transitive dependency 함정**: 핀 필요 라이브러리는 transitive도 매트릭스에 명시. 특히 **`numpy<2`** — YOLO `ultralytics`가 numpy<2를 요구하지만 대부분 최신 라이브러리는 numpy>=2를 끌어옴. `pip install` 순서에 따라 silent 업그레이드 발생 → ultralytics import 시점 런타임 실패. 모든 Python venv 셋업 마지막에 `numpy<2` 재핀 + import 검증 필수.

9. **State-changing 명령은 명시적 confirm** — `sudo reboot`, `apt purge`, NVIDIA 드라이버 교체, Docker 데몬 재시작처럼 되돌릴 수 없는 작업은 사용자 confirm prompt 없이 자동 실행 금지. 진행 중 작업 / unsaved state 손실 방지.

10. **No hardcoded secrets** — OpenAI / Anthropic API key, GitHub PAT 등 자격증명은 스크립트에 절대 박지 않는다. `.env` 또는 사용자 환경변수에서 로드. `.env`는 절대 커밋 금지 (`.env.example`이 템플릿).

11. **No AI attribution in git artifacts** — commit message, PR description, AUTHORS / CONTRIBUTORS 자리에 Claude / Copilot / GPT / 기타 AI assistant를 `Co-Authored-By`, contributor, "Generated with X" footer로 추가하지 않는다. Commit / PR은 사용자 명의로만. git history는 비가역이라 amend / force-push 같은 destructive 복구가 필요해진다.

## Quick Ref

- Entry (권장): `bash install.sh` — **base 환경**만 단일 시퀀스(`[n/9]`)로 실행(kernel/NVIDIA/Docker/ROS2 + reboot + VS Code + DDS + 정적 IP). 시작 시 confirm 1회, 이후 자동 진행. step 6 에서 1회 자동 reboot → 복귀(로그인) 시 GUI autostart 로 자동 재개(GUI 세션 필요, 복귀 후 sudo 비번 1회). OPENAI 키는 인스톨러가 다루지 않음(사용자가 voice_processing 패키지 resource/.env 에 직접 배치 — 별도 안내). autostart 등록 불가 환경이면 reboot 후 `bash install.sh` 재실행(완료 step 자동 skip). 옵션: `--status`/`--reset`/`--verbose`(`VERBOSE=1`)/`--help`. 콘솔엔 `[n/total]` 진행률만(상세 출력은 레포 루트 `install_log`). 단계 실패 시 `[FAIL]` + 로그 경로, 종료 시 로그 경로 1회.
- 애플리케이션 셋업: `bash setup-app.sh` — 워크스페이스 7 단계(`obtain_cobot2`(수동 배치 검증) → `obtain_m0609`(m0609 레포 clone + `m0609_rg2_bringup` 심볼릭 링크 + `onrobot-ros2` SHA 핀 clone) → `app-install.sh dsr`(DSR 드라이버) → `app-install.sh realsense-sdk`/`realsense-ros` → `app-install.sh voice` → `app-install.sh colcon`) + 컨테이너(`app-install.sh toolkit` → `containers/build-all.sh`(`:dev-builder` 이미지 빌드 + 검증)). 플래그 `--workspace-only`/`--containers-only`/`--reset`(install.sh `--reset` 와 이름 통일)/`-y`/`--help`. `--reset` 은 doosan-robot2 + onrobot-ros2 clone + m0609 심볼릭 링크를 지우고, cobot2 와 `${M0609_REPO_DIR}` 원본은 보존한다. (구 `reinstall-workspace.sh` 흡수·폐기. prebuilt `--fetch` 경로는 dev-builder 단일 모델로 통합하며 폐기.)
- 통합 실행 진입점: `bash containers/bringup.sh [launch args]` — host voice 노드 + yolo 컨테이너와 함께 `ros2 launch m0609_rg2_bringup bringup.launch.py` 실행(구 `cobot2_bringup bringup_all.launch.py` 대체). 사용자가 `camera:=` 를 안 주면 `camera:=true` 를 덧붙인다 — 새 launch 의 camera 기본값은 false 인데 yolo 노드는 카메라 토픽(`/camera/*` — 2026-07-21 `/camera/camera/*` 에서 변경)이 없으면 조용히 대기만 하기 때문. 같은 스크립트가 yolo 노드를 `--ros-args -r img_node:__ns:=/camera` 로 띄운다 — 신본 `ImgNode` 는 절대 경로를 구독해 이 인자가 없어도 되지만, 구 소스(상대 이름)가 깔린 머신을 위해 전환기 동안 남겨 둔다(절대 이름은 네임스페이스 remap 의 영향을 안 받아 양쪽 다 동작).
- 단계 재실행: `bash install.sh` 재실행 시 완료 step 은 state 기준 자동 skip 되어 끊긴 지점부터 이어진다. 특정 작업만 강제 재실행은 `--reset`(전체 초기화) 또는 해당 서브커맨드 직접 실행(예: `bash resources/base-install.sh vscode`).
- 순차 의미: install.sh = `a01(1-5) → reboot(6) → a03 vscode(7) → dds(8) → network(9)`. (구 a02=DSR/RealSense/colcon, a04=voice·OPENAI key 는 install.sh 에서 제거 → voice 는 `setup-app.sh`(host 설치), OPENAI key 는 사용자 수동 배치(voice_processing 패키지 `resource/.env`).) `run_step` 은 `resources/lib.sh`(state + run_step + step 정의 + 사용자 확인 + apt repo 등록 통합)로 중앙화(install.sh 가 `STEPS_TOTAL` 만 설정).
- 정적 검증: `shellcheck *.sh resources/*.sh scripts/*.sh`
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
- 셸 스크립트 작성/리팩토링 규약은 `docs/SCRIPTING_GUIDELINES.md` 참조 (멱등 가드 패턴, 메시지 prefix, `set -euo` 예외, `add_apt_repo` 사용법, 신규 스크립트 템플릿).
- 새 단계 추가 시 `total` 카운트와 진행률 표시 동시 갱신 (Hard Rule #4).
- 새 외부 repo / Docker image 도입 시 `docs/COMPATIBILITY.md` 매트릭스 갱신 (Hard Rule #8).
- 로그는 append-only — 각 step 의 상세 stdout/stderr 는 `lib.sh` 의 `run_step` 이 `~/.cobot2_jazzy_installer/install.log` 로 append(콘솔엔 `[n/total]` 진행률 + 경고/에러만). 덮어쓰기 (`> install.log`) 금지.
- 커밋은 한 논리 변경 단위로 분리 (예: "RealSense distro 패치"와 "DSR 의존성 갱신"은 다른 커밋).
- 커밋은 사용자 명시적 요청 시에만 (Hard Rule #11).
- **커밋 메시지는 외부 사람이 이해 가능하게 작성** — 내부 마일스톤 코드 (M1, M2), 결정 기록 번호 (ADR-NNN), 단계 번호 (Phase N), 룰 ID (Hard Rule #N) 같은 본 레포 내부 축약어 미사용. 기능 단위로 분할. 한국어 회화 + 영어 식별자 혼용.
- **remote = public 2개** (2026-08-11 결정 변경) — 배포처가 `ROKEY-SPARK/cobot2_jazzy_installer`(`rokey`), 개인 사본이 `Seooooooogi/ros2_jazzy_test`(`origin`). 둘 다 public. 공개 대상은 **`main` 브랜치뿐** — `docs/`·`CLAUDE.md`·`.claude/`·`scripts/`·`tasks/`·`backup/` 는 `.claude-main-exclude` 로 main 에서 빠진다. push 전 secret 스캔 필수(공개는 비가역이라 사후 회수가 불가능하고, 히스토리에 한 번 들어간 키는 force-push 로도 캐시가 남는다). 신규 remote 추가는 사용자 명시 동의 필요.
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
