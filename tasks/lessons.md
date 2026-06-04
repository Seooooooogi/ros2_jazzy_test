# tasks/lessons.md — AI 행동 교정 규칙

> 반복 실수가 발생하면 여기에 기록 → 다음 세션 SessionStart hook이 자동 노출.
> 작성 패턴:
> - **Symptom**: 어떤 잘못된 행동이 반복되었는가
> - **Why it happened**: 모델이 그 행동을 한 추정 원인
> - **Correction**: 다음부터 어떻게 행동해야 하는가
> - **Trigger**: 이 교정이 발동되어야 하는 상황 (키워드 / 작업 종류)

---

## L-001: Notion `insert_content` 큰 페이로드 → Cloudflare 차단

- **Symptom**: 한 번에 ~10KB+ 크기의 markdown 을 `mcp__claude_ai_Notion__notion-update-page` `insert_content` 로 보내면 Cloudflare 가 차단 응답 (HTML "Sorry, you have been blocked", Ray ID 동반).
- **Why it happened**: 페이로드 크기 + 일부 WAF 트리거 패턴 (shell 명령 라인 / `<script>` 유사 토큰 등) 의심.
- **Correction**: 5-7개 섹션으로 분할하여 `insert_content` 를 순차 호출 (각 청크 ~50줄 이하 권장). 첫 청크가 통과하면 나머지도 같은 호출 패턴으로 안전.
- **Trigger**: "노션에 보고서 만들어줘", "notion 페이지에 정리", "notion 페이지에 넣어줘", `mcp__claude_ai_Notion__notion-update-page` 의 `insert_content` 호출.

---

## L-002: Mermaid edge label 안의 `--` → 화살표 토큰으로 오인 → 구문 오류

- **Symptom**: 노션 / GitHub 의 mermaid 렌더러가 다음 같은 라인에서 "syntax error" 표시:
  ```
  SRC -- docker compose build --pull --> BUILD
  ```
  사용자 의도: `--` 사이의 문자열 ("docker compose build --pull") 이 edge label. 그러나 라벨 안의 `--pull` 의 `--` 가 mermaid parser 에게 화살표 시작 토큰으로 보임 → edge 정의가 깨짐.
- **Why it happened**: Mermaid 의 `A -- text --> B` 문법은 양쪽 `--` 를 edge 경계로 인식. 라벨 자체에 `--` 가 들어가면 parser 가 어디서 라벨이 끝나는지 헷갈림. CLI flag (`--pull`, `--force`, `--no-deps` 등) 이 흔한 trigger.
- **Correction**: **pipe 문법으로 작성**: `A -->|text with --| B`. pipe `|` 가 명시적 경계라 라벨 안에 `--` 가 자유롭게 들어감. 또는 라벨에서 `--` 를 단일 `-` / em-dash (`—`) 로 변경해 회피 (단 의미 손실 가능).
- **Trigger**: Mermaid flowchart 의 edge label 에 shell 명령 / CLI flag / 옵션 (`--pull`, `--force`, `--no-deps`, `--system-site-packages`) 을 넣을 때. 노션에 mermaid 다이어그램 작성 / GitHub README 의 flowchart 작성 시.

---

## L-003: 다중 편집 Notion 페이지 → `update_content` 직전 재-fetch 필수

- **Symptom**: 세션 초반에 fetch 한 페이지 내용으로 `update_content` 의 `old_str` 을 구성했는데, 그 사이 다른 담당자가 섹션을 새로 채워 넣어 (예: `<empty-block/>` → 충실한 표) old_str 매칭 실패 (`No matches found`). 매칭 실패가 안 났다면 남의 작업을 덮어쓸 뻔함.
- **Why it happened**: Notion 페이지는 공동 편집 대상. 세션 시작 시점 fetch 는 스냅샷이라 시간이 지나면 stale. 담당자 2명 이상이면 분 단위로 내용이 바뀜.
- **Correction**: 공유 Notion 페이지를 `update_content` / `replace_content` 로 수정하기 직전 **항상 재-fetch** 하여 현재 상태로 old_str 을 재구성. 특히 빈 섹션(`<empty-block/>`)을 채울 때는 누가 이미 채웠는지 확인 후 진행 — 덮어쓰기 대신 surgical 정정.
- **Trigger**: 담당자 2명 이상인 Notion 페이지 수정, 세션 중반 이후의 `mcp__claude_ai_Notion__notion-update-page` `update_content`/`replace_content`, `<empty-block/>` 를 콘텐츠로 교체하려는 경우.

---

## L-004: 정적 검증(shellcheck) 통과를 "동작 확인 / 완료"로 보고 금지

- **Symptom**: M2 시스템 레이어 스크립트가 `shellcheck -x` 0 findings + `bash -n` OK 였으나, 실제 `a01-prerequirements.sh` 실행 시 버그 4건이 연속으로 터짐 — (1) `nvidia-driver-NNN-open` 패키지명 미인식, (2) `python3-ament-package`(noble 부재), (3) sudo 실행 시 HOME=/root 오염, (4) hold 된 `hi` 상태를 미설치로 오판.
- **Why it happened**: shellcheck/bash -n 는 문법·일부 안티패턴만 본다. 패키지명 실재 여부, dpkg 상태 의미, 런타임 환경(sudo/HOME/그룹)은 못 잡는다. "정적 통과"를 "동작"으로 착각해 보고.
- **Correction**: installer/시스템 스크립트는 **정적 검증 통과 ≠ 동작**. 완료 보고 시 "shellcheck 통과"와 "실제 실행 확인"을 명확히 구분. 이 머신이 곧 타깃이므로 가능하면 실제 실행으로 확인. 사용자 검증 원칙(각 Phase = cobot2_ws/실행 동작)과 정확히 일치 — 정적은 게이트, 동작이 acceptance.
- **Trigger**: bash installer / 시스템 셋업 스크립트 작성 후 완료 보고. "검증했다 / 통과했다" 표현 쓰기 직전.

---

## L-005: apt 패키지 처리 함정 — dpkg `hi`(hold+installed) + distro별 패키지명

- **Symptom**: (a) `apt-mark hold` 건 패키지는 dpkg status-abbrev 가 `ii` 가 아니라 **`hi`** → `$1 ~ /^ii/` 로 설치 판정하면 미설치로 오판 → 재설치 시도 → hold 충돌(무한 루프). (b) humble 패키지명(`python3-ament-package`)이 jazzy/noble repo 엔 없음(`ros-jazzy-ament-package` 임).
- **Why it happened**: (a) 스크립트가 직접 hold 를 거는데 그 결과 상태(`hi`)를 자기 검사가 못 잡는 자가당착. (b) distro 마다 패키지명/제공 형태가 다른데 humble 기준을 그대로 가정.
- **Correction**: dpkg 설치 여부는 status-abbrev **2번째 글자 = `i`** 로 판정(`$1 ~ /^.i/`). 패키지명은 사용 전 `apt-cache policy <pkg>` 로 해당 distro 에서 사전 검증(sudo 불필요) — 한 번에 전부 확인해 fail-fix-rerun 반복 회피.
- **Trigger**: `apt-mark hold` + dpkg 설치 상태 체크, humble→jazzy(이후 distro) 패키지명 마이그레이션, `ros-humble-*` → `ros-${ROS_DISTRO}-*` 치환.

---

## L-006: apt repo "Release 도달 OK" ≠ "서명 키 일치" — vendor 분사/키 로테이션 함정

- **Symptom**: RealSense SDK 설치(`realsense-sdk-install.sh`)가 `apt-get update` 에서 `NO_PUBKEY FB0B24895113F120 ... repository is not signed` 로 실패. 사전 검증(ADR-003) 때 `curl -fsI .../dists/noble/Release` 200 OK 만 보고 "noble 지원 활성" 으로 판단했으나, 정작 keyring 에 든 키(`librealsense.intel.com/.../librealsense.pgp` = 2018 Intel 키 C8B3A55A...)와 repo 서명 키(2025-11 신 키 …FB0B24895113F120, `@realsenseai.com`)가 불일치.
- **Why it happened**: (1) 검증을 "repo HTTP 도달" 수준에서 멈춤 — 키 fingerprint 가 repo InRelease 서명과 일치하는지까지 안 봄. (2) **vendor 분사**: 2025-11 Intel RealSense → RealSense AI 분사로 apt 도메인(`librealsense.intel.com`→`librealsense.realsenseai.com`)과 서명 키가 동시 교체됐는데, 구 정적 키 URL 은 옛 키를 계속 서빙. humble 시절 문서/스크립트의 키 URL 을 그대로 가정.
- **Correction**: 외부 apt repo 키 검증은 **fingerprint 대조까지** 수행 — `gpg --show-keys <keyfile>` 의 fpr 와 repo InRelease 서명 키 ID 비교. 불일치 시 공식 현행 문서(예: `IntelRealSense/librealsense/doc/distribution_linux.md`)에서 **현재** 키 URL/도메인 재확인. armored `.asc` 는 `gpg --dearmor` 후 `signed-by`. 실패 run 이 남긴 구 source list/keyring 은 다음 `apt-get update` 를 또 막으므로 스크립트가 `apt-get update` **전에** 제거(idempotent).
- **Trigger**: 외부 vendor apt repo (NVIDIA / Docker / RealSense / ROS 등) 의 키링 + signed-by 구성. "repo 도달 확인했다 / 활성이다" 표현 직전. distro 마이그레이션 시 humble 시절 키/도메인 URL 을 재사용하려 할 때. `NO_PUBKEY` / `is not signed` 에러.

---

## L-007: ROS2 인터페이스 패키지 검증 — `ros2 interface show` 실패 ≠ 런타임 고장

- **Symptom**: a02 빌드 후 `ros2 interface show od_msg/srv/SrvDepthPosition` → `Unknown package 'od_msg'`. od_msg 가 빌드 안 됐거나 못 쓰는 것으로 오판할 뻔함. 실제로는 od_msg 가 정상 빌드됐고 `from od_msg.srv import SrvDepthPosition` 및 `node.create_client(SrvDepthPosition, ...)` 가 모두 동작(typesupport 로드 OK).
- **Why it happened**: `ros2 interface`/`ros2 pkg` CLI 는 **AMENT_PREFIX_PATH(ament index)** 로 패키지를 찾는다. 반면 ROS2 노드는 서비스/메시지 타입을 **Python import(PYTHONPATH)** + typesupport(.so, LD_LIBRARY_PATH) 로 소비한다. od_msg 의 `ament_package()` 가 merged colcon setup 의 package.dsv 에 `local_setup`(ament_prefix_path 훅) 대신 legacy catkin식 훅(ros_package_path/catkin_pythonpath/pkg_config)을 생성해 AMENT_PREFIX_PATH 만 누락 → CLI introspection 만 깨지고 런타임은 멀쩡. 검증을 CLI introspection 으로만 했으면 멀쩡한 배포를 "고장" 으로 보고했을 것.
- **Correction**: 인터페이스 패키지 검증은 **런타임 사용 경로**로 한다 — `python3 -c "from <pkg>.srv import <Type>"` (import) + 필요시 `rclpy` 로 `create_client/create_service` (typesupport 로드 확인). `ros2 interface show` 는 보조 지표일 뿐, 실패해도 PYTHONPATH/typesupport 가 export 되면 동작한다. 빌드 산출물(`install/<pkg>/lib/python3.12/site-packages/<pkg>/`)과 `package.dsv` 의 `local_setup` 유무를 같이 확인. (프로젝트 검증 원칙 = cobot2_ws 실제 동작과 정합.)
- **Trigger**: ROS2 custom 인터페이스(msg/srv/action) 패키지 빌드 후 검증. `ros2 interface show` / `ros2 pkg list` 가 패키지를 못 찾을 때 — "안 됐다" 단정 전에 Python import 로 재확인.

---

## 예상 후보 (발생 시 정식 항목으로 승격)

본 프로젝트가 Phase 2 마이그레이션 단계에서 실제 작업이 진행되면, 발견되는 반복 실수를 이 파일에 누적.
- distro 문자열을 하드코딩으로 다시 박는 경우 (Hard Rule #1 위반)
- `pip install` 을 numpy 재핀 단계 **앞**에 추가하는 경우 (ADR-002 위반)
- Docker 이미지를 무태그 또는 `latest` 로 두는 경우 (Hard Rule #6 위반)
- bash 스크립트 최상단에 `set -euo pipefail` 누락 (Hard Rule #5 위반)

---

## L-00X: "hang" 오판 — python stdout block-buffering (2026-06-02)

- **Symptom**: DSR_ROBOT2 prefix 패치 후 `python3 ... | grep ... | tail` 로 검증했더니 "Terminated"만 떠 아직 hang 으로 오판. 실제로는 `get_current_posj()` 성공이었고 출력이 파이프 버퍼에 갇혀 timeout kill 시 유실된 것.
- **Why it happened**: python stdout 은 tty 가 아니라 파이프로 갈 때 line-buffered 가 아니라 block-buffered. 중간 print 가 flush 안 된 채 프로세스가 죽으면 통째로 사라진다.
- **Correction**: ROS/로봇 서비스 호출처럼 "hang 인지 성공인지" 가리는 진단은 `python3 -u` + `print(..., flush=True)` 로 강제 unbuffered. "Terminated만 보임 = hang" 으로 단정 금지.
- **Trigger**: 파이프로 받은 python/ROS 스크립트가 멈춘 듯 보일 때, service call / spin_until_future_complete 진단 시.

## L-00Y: DSR 서비스 "있는데 응답 없음" → short name vs dsr_controller2/ prefix (2026-06-02)

- **Symptom**: `ros2 service list` 에 `/dsr01/aux_control/get_current_posj` 가 보이는데 호출하면 무한 대기. 같은 기능의 `/dsr01/dsr_controller2/aux_control/...` 는 정상 응답.
- **Why it happened**: short name 은 클라이언트(jog 노드)가 만든 항목일 뿐 서버가 없음. 실서버는 컨트롤러 노드 네임스페이스(`dsr_controller2/`) 아래. service list 에 이름이 보인다고 서버가 있는 게 아니다.
- **Correction**: DSR 서비스 hang 시 `ros2 node info <노드>` 로 **누가 서버하는지** 먼저 확인. 이름만 보고 서버 존재 단정 금지. DSR_ROBOT2 의 `_srv_name_prefix` 가 컨트롤러 네임스페이스와 맞는지 점검.
- **Trigger**: DSR/ROS2 service call timeout, get_current_pos*/movej hang, bringup 후 통신 안 될 때.

---

## L-008: `ros2 topic hz` 대용량 토픽 저수치 = 측정/전송 계층 artifact (≠ 카메라·노드 성능) (2026-06-04)

- **Symptom**: RealSense raw 토픽(`color/image_raw`, `depth/image_rect_raw`, `depth/color/points`)을 `ros2 topic hz` 로 재니 30fps 설정인데 4\~14Hz 로 출렁여 카메라/노드 성능 문제로 오판할 뻔. 실제로는 카메라·노드가 30fps 정상 publish — 같은 콜백에서 나오는 `camera_info`(작은 메시지)는 모든 설정에서 29.98Hz 안정.
- **Why it happened**: (1) `ros2 topic hz`(rclpy 단일 스레드)가 대용량 메시지(color 1프레임 ≈ 2.6MB) 역직렬화를 publish 속도만큼 못 따라가고, 센서 토픽 기본 QoS 가 best-effort 라 놓친 프레임은 드랍 → 실제보다 낮게·측정마다 출렁. (2) CycloneDDS 로 바꾸자 raw 가 아예 0Hz — UDP fragment 재조립용 OS socket 버퍼(`net.core.rmem_max` 기본 ~208KB)가 1프레임보다 작아 전량 유실. (3) 측정 쉘과 노드의 RMW 가 다르면 통신 자체가 안 됨.
- **Correction**: 대용량 토픽 fps 진단은 **작은 동반 토픽(`camera_info`/`metadata`) hz 로 교차검증** — 작은 메시지는 전송 계층 영향이 없어 실제 프레임레이트를 그대로 반영(image 와 동일 콜백). raw 토픽을 정확히 재야 하면 ① 측정 쉘과 노드의 `RMW_IMPLEMENTATION` 일치, ② CycloneDDS 면 `sudo sysctl -w net.core.rmem_max=2147483647` + `CYCLONEDDS_URI` 의 `SocketReceiveBufferSize` 상향. `RMW_IMPLEMENTATION`·`CYCLONEDDS_URI` 는 **쉘(프로세스)별 환경변수** 라 측정 터미널마다 export 해야 함(한 쉘의 export 가 다른 터미널로 전파 안 됨). "낮은 hz = 카메라 느림" 단정 금지.
- **Trigger**: `ros2 topic hz` 로 이미지/pointcloud 등 대용량 토픽 측정, RealSense/카메라 fps 검증, RMW 변경(fastrtps ↔ cyclonedds) 후 토픽 수신 이상, 토픽이 "안 보임 / 0Hz" 로 나올 때.
