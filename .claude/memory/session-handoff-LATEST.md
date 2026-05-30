# Session Handoff — LATEST

> 매 세션 종료 전 `/session-checkpoint` 로 갱신. 글로벌 `SessionStart` hook 이 자동 로드.
> Forward-looking only — 본 세션에서 한 일이 아니라 다음 세션이 할 일.

## Last updated
2026-05-30 — **Phase 4 컨테이너 "빌드 게이트" 완료** (host 무관 빌드 + 개별 검증). yolo/voice 멀티스테이지 Dockerfile + `containers/{entrypoint.sh, docker-compose.yml, build-all.sh}` + 루트 `.dockerignore` 신설, `cobot2_ws` 빌드버그 4건 수정. 두 이미지 실제 빌드 + import smoke + secret 위생 PASS (`local/ros2-jazzy-{yolo:13.6GB, voice:1.89GB}:dev`). 결정: **ADR-009** (base `ros:jazzy-ros-base-noble` 단일 / network host / od_msg 원본보존+Dockerfile 우회 / 빌드게이트 경계). 3 논리 커밋 → **feature 브랜치 `feat/application-containers` 로 origin push** (pre-push 파이프라인 통과, main 은 origin/main 그대로 유지). 빌드는 `bash containers/build-all.sh` (compose 플러그인 host 미설치 → docker build 직접).
> 이전(2026-05-29): GitHub private 동기화로 Phase 2 (M1~M5) 구현 완료, ADR-006/011/012.

---

## Next Actions (priority order)

1. **`feat/application-containers` 처리 결정** — 사용자가 의도적으로 main 을 비켜 push. PR 생성(`gh pr create`) / main merge / 계속 iterate 중 선택. PR 링크: `https://github.com/Seooooooogi/ros2_jazzy_test/pull/new/feat/application-containers`.
2. **Phase 3 — host installer end-to-end 실제 실행 검증** (ROADMAP 3-2, 3-3): `bash install.sh` 전체 `[n/11]` 실행 (reboot 포함), 중단-재개(`--status`/`--reset`) 검증. acceptance = cobot2_ws 실제 동작 (L-004, 이 머신이 타깃). **Phase 4 통합(step 5)의 선결** — 컨테이너 acceptance 가 host 의 a01/a02 동작에 의존.
3. **Phase 4 통합 (step 5, host e2e 이후)** = 진짜 Phase 4 PASS. 빌드게이트에서 미룬 것 전부:
   - GPU 런타임: `docker run --gpus all <yolo> python3 -c "import torch; assert torch.cuda.is_available()"` (nvidia-container-toolkit + host driver 필요)
   - service 왕복: host `robot_control`(client) ↔ 컨테이너 `/get_3d_position`(od_msg/SrvDepthPosition) + `/get_keyword`(std_srvs/Trigger). network_mode:host DDS.
   - **od_msg type hash 정합**: host(robot_control)·yolo 가 동일 `cobot2_ws/od_msg` 빌드해야 일치. 불일치 시 `wait_for_service` 무한 차단.
   - 카메라 USB passthrough (`/dev/bus/usb`) + 마이크 PipeWire socket mount (`${XDG_RUNTIME_DIR}/pulse`). compose 에 주석으로 placeholder 있음 → 활성화.
   - publish: `docker login` + tag(semver/SHA) + push (ADR-007). `.env` 에 DOCKERHUB_USER/TOKEN.
4. **Phase 3 산출물 — `docs/TROUBLESHOOTING.md`** (3-1): L-004~L-008 의 실행 버그 카탈로그화.
5. **보류된 MINOR** (이번 리뷰): smoke assertion `int(major)==1` 강건화, cobot2_ws 의 ROS2 `print()`→`get_logger()`(기존 코드), build-all `--help`, pip lock 파일(transitive 완전 잠금).

---

## Current Work State

- 코드 변경 없음 (in-progress 작업 없음). 모든 빌드게이트 작업은 `feat/application-containers` 에 커밋+push 완료.
- **`.claude/memory/{MEMORY.md, session-handoff-LATEST.md}` 만 미커밋** (이 체크포인트 갱신분). 세션 메모리라 의도적 비커밋 — 다음 세션이 커밋하거나 그대로 둠.

---

## Open Decisions

- **`feat/application-containers` disposition**: PR / merge / iterate (사용자 결정 대기).
- **Phase 4 통합 세부** (step 5 진입 시): 마이크 `device_index=10` 하드코딩(MicController/get_keyword) → 컨테이너에서 동적 매핑/PipeWire 필요. 카메라 USB passthrough 구체.
- ~~Phase 4 디자인 3건 (base/network/install.sh 자동호출)~~ → **전부 해결**: (a) base = `ros:jazzy-ros-base-noble` 단일 (ADR-009), (b) network = host (ADR-009), (c) install.sh 자동호출 안 함 — build-all/compose 분리 (ADR-007/ROADMAP 4-6).

---

## Remaining Issues

- **통합 미해결 소스 이슈** (step 5 에서 처리, 빌드게이트엔 무관):
  - YOLO 가중치 `yolov8n_tools_0122.pt` 가 `cobot2_ws/object_detection/resource/` 에 **없음** — `cobot2_ws/pick_and_place_text/resource/` 에만 존재(6MB). 런타임 `YoloModel()` 인스턴스화 시 FileNotFoundError. mount 또는 복사 필요 (ROADMAP 4-1: image 에 안 박고 mount).
  - `object_detection` 이 `realsense2_camera` 노드를 직접 안 띄움 (launch 없음, `/camera/camera/*` subscribe 만). 컨테이너에서 카메라 노드 별도 기동 필요.
- **ROADMAP 체크박스 미반영 (Phase 2 분)**: 2-1/2-2/2-3/2-4/2-5/2-7/2-11~2-15 가 `[ ]` 인데 작업 완료. Phase 3 진입 전 reconcile (활성 버그 아님).
- yolo 이미지 13.6GB — nvidia CUDA 런타임 ≈4.2GB 가 floor (GPU torch 불가피). 안전 슬림 한계 도달.
- 활성 런타임 버그 없음.

---

## Context Notes (다음 세션 전제)

### Phase 4 빌드게이트 산출물 (2026-05-30)
- `containers/yolo-detection/Dockerfile`, `containers/voice-processing/Dockerfile` (멀티스테이지 builder→runtime, base `ros:jazzy-ros-base-noble`). 빌드 context = repo 루트, COPY `cobot2_ws/{od_msg,object_detection}` / `cobot2_ws/voice_processing` + `containers/entrypoint.sh`.
- 빌드 = `bash containers/build-all.sh` → docker build ×2 + secret grep + 컨테이너 내부 import smoke. **compose 플러그인 host 미설치** (docker 29.1.3, compose 없음) → build-all 은 `docker build` 직접. compose 는 런타임(up) 단계용.
- 컨테이너 pip 의존 핀: numpy<2(마지막 재핀), opencv-python<4.10(numpy>=2 메타 충돌 회피), ultralytics<9, langchain<2/openai<3. 실측 버전표 = `docs/COMPATIBILITY.md`.
- **빌드게이트 ≠ Phase 4 PASS**: 빌드+import smoke+secret 까지만. GPU/service/hash/passthrough/publish 는 host e2e 이후 (위 Next Action 3).

### git 운영 (2026-05-30)
- **feature branch workflow 사용 시작**: `feat/application-containers` (origin push 됨, upstream 설정). main 은 origin/main(dc8fa19) 유지 — 사용자가 작업을 main 직접 반영 대신 브랜치로 분리 선호.
- `gh` CLI 설치 + 인증 완료 (Seooooooogi, ssh). `origin` = `git@github.com:Seooooooogi/ros2_jazzy_test.git` (private, ADR-012).
- 커밋: 사용자 명의만, AI attribution 금지 (하네스 기본 Co-Authored-By trailer 미적용). 메시지 외부 친화 (내부 축약어 미사용).
- 백업 브랜치 `backup/pre-github-sync-2026-05-29` 존재 (검토 후 삭제 가능).
- push 전 `pre-push` 스킬 (시크릿 스캔 + code-reviewer) 필수. 스킬은 staged diff 기준이나 commit 후 push 시 `git diff origin/main..HEAD` 로 payload 스캔.

### 검증 함정 (lessons.md 참조)
- **L-004** 정적 통과 ≠ 동작 / **L-005** apt hold `hi` / **L-006** apt 키 fingerprint / **L-007** ROS2 인터페이스 import 검증 / **L-008** Dockerfile RUN 의 `set -u` + ROS setup.bash 충돌.

### 도메인 사실 (step 5 통합 시 전제 — 유효)
- doosan-robot2: host↔controller = TCP 12345 via DRFL (DDS 아님). clone `-b jazzy`, emulator `3.0.1` `profiles:[dev]`.
- librealsense2 = Intel noble apt 정식. Voice 입력 = 노트북 내장 마이크 (PipeWire socket mount).
- 호스트 = RTX 4060 Laptop (sm_89). host↔container 통신 = 2개 ROS2 service (topic 아님). 카메라 `/camera/camera/*` 는 yolo 컨테이너 내부에서 닫힘.

---

## Current Focus
- **Top priority**: `feat/application-containers` 처리 결정 + Phase 3 host e2e 검증 (Phase 4 통합 acceptance 의 선결 — torch.cuda/service/hash 전부 host 의존).
- **Friction**: Phase 4 PASS 는 host e2e 없이는 측정 불가. 통합 소스 이슈(가중치 위치, device_index, 카메라 노드 기동) 가 step 5 에서 추가로 드러날 것.
