# Session Handoff — LATEST

> 매 세션 종료 전 갱신. 글로벌 `SessionStart` hook 이 자동 로드.
> Forward-looking only — 본 세션에서 한 일이 아니라 다음 세션이 할 일.
> 두 머신 공유 — **[실측]** 머신(로봇/카메라 실기) + **[문서]** 머신(git/문서/lessons). 항목에 담당 표기.

## ⚠ 다음 세션 — 무엇보다 먼저 (사용자 지시 2026-06-10)
**사용자가 내일 어떤 명령/요청으로 시작하든, 본론 전에 먼저 이걸 안내하고 확인받은 뒤 진행한다:**

→ **YOLO 이미지 재빌드 + 드라이브 재업로드.** yolo.py KeyError 수정(`1de572b`)이 소스엔 반영됐지만 **드라이브의 yolo 이미지는 옛 버전** → 클린설치 fetch(step 15)가 옛 이미지를 받아 수정 미반영. 적용 절차:
1. `set -a; source resources/config.sh; set +a; bash containers/build-all.sh` — yolo 재빌드(Dockerfile 레이어상 torch 재다운로드 가능, 수십 분).
2. `docker save local/ros2-jazzy-yolo:dev -o /tmp/yolo.tar` — tar ≈ 4.3GB(`DOCKERHUB_USER` 설정 시 그 태그로).
3. `sha256sum /tmp/yolo.tar` → `resources/config.sh` 의 `YOLO_IMAGE_SHA256` 갱신(새 파일로 올리면 `YOLO_IMAGE_GDRIVE_ID` 도). 변경 커밋/푸시.
4. **`/tmp/yolo.tar` 를 공개 구글 드라이브에 업로드 — 사용자 Drive 계정 작업(AI 가 4.3GB 업로드 못 함).** 기존 file ID 자리에 교체 또는 새 파일+ID 갱신. "링크 있는 사람 보기" 공유 확인.
- **대안**: 검증 머신에서 fetch 대신 `bash containers/build-all.sh` 로 로컬 빌드(드라이브 round-trip 회피, 더 빠를 수 있음).

## Last updated
2026-06-11 — **[문서]** 전부 origin push 완료(branch `feat/application-containers`, 4커밋):
① **DDS 도메인 단일값 일치**(`43fa06c`) — `.env.example` 의 `ROS_DOMAIN_ID` 예시가 `0` 이라 살려 쓰면 host(기본 42)와 컨테이너가 다른 도메인에 떠 노드가 조용히 서로 못 찾던 풋건. 예시를 `42`(단일 진실 소스 = `resources/config.sh`)에 맞추고 "바꾸면 host·양 컨테이너 동일 값 유지" 경고 주석 추가.
② **문서 정정** — README 실기 기동 예시 placeholder `<controller-ip>`→실제 `192.168.1.100`(`ad562cd`); 결정기록(`docs/decisions`) 검증 명령 `docker exec rokey-yolo`→`docker compose exec yolo-detection`(`9d01749`).
③ **gitignore 위생**(`3907af1`) — 로컬 도구 산출물/캐시(`.agents/`, `.understand-anything/`, `.claude/skills/`+`skills-lock.json`, `backup/llm_wiki/`) 추적 제외. `.claude/memory`·`backup/` 보존 스크립트는 서브경로만 타깃이라 추적 유지.
④ **Notion 문서 동기화**(git 무관·원격 반영) — 마이그레이션 페이지 §2-1 아키텍처/§3-1 host 순차설치/§4 폴더구조를 16-step + 그리퍼(.1)/ALSA 마이크/wakeword 토픽/loopback 용어로 갱신; Docker 페이지를 실제 코드(멀티스테이지 Dockerfile·compose·`cobot2_ws` 구조)로 전면 교체 + "기동 순서 견고성"(DDS 비동기 discovery·RMW 통일·`wait_for_service` 블로킹으로 서순 무관, 단 카메라/생산자 영영 부재 시 조용한 hang) 분석 섹션 추가; 서비스 메시지 페이지에 wakeword 설명 삽입.
직전 2026-06-10: DDS 인터페이스=loopback+물리 NIC(ADR-020), ethernet 고정 IP 자동화(install.sh step16·STEPS_TOTAL 15→16), 무인 설치 `--unattended`, OPENAI_API_KEY 처리 버그 수정, fetch 진행바 제거, YOLO KeyError 수정(소스만 — 이미지 재빌드 미반영, 상단 ⚠). 직전 2026-06-09: voice 컨테이너 e2e + cobot2_bringup 분리 + 드라이브 이미지 fetch 전환.

---

## Next Actions (priority order)

1. **[실측] 전체 클린설치 검증 — 다른 노트북(fleet 머신)에서 진행** — 최신 origin `git clone` → `bash install.sh`. 새 머신엔 이미지가 없어 **step14 가 드라이브에서 실제 다운로드**(yolo 4.4GB 첫 실측 자연 발생 — `docker rmi` 불요). nvidia-container-toolkit 은 step14(reboot 이후)에서 자동 설치(SKIP_IF_NO_GPU=1 — GPU 없으면 정상 skip). a01(step1~6) NVIDIA+reboot destructive, step12 `.env` OPENAI_API_KEY interactive. **점검: 드라이브 파일 2개가 "링크 있는 사람 보기" 공유여야 다른 네트워크/무계정에서 무인 curl 가능**(이 머신 fetch 성공은 동일 계정/네트워크 영향 배제 못 함). **(2026-06-10 갱신)** 이제 **전체 16 step**(step 15 드라이브 fetch, **step 16 ethernet 고정 IP** `192.168.1.30/24` 자동). `bash install.sh --unattended` 로 reboot·재개 무인 가능(GUI 세션, 복귀 후 sudo 비번 1회). **OPENAI_API_KEY 처리 버그 수정됨** — 쉘 env 에 키가 있든 `.env.example` 에 잘못 넣든 자동 처리 → 지난번 voice crash-loop 재발 안 함. yolo KeyError 도 미검출 처리(단 이미지 재빌드 전엔 옛 이미지 — 상단 배너 참조).

2. **[실측/문서] cobot2_bringup 클린설치 자동 빌드 검증** — `dsr-project-install.sh` HOST_PKGS 에 등록됨(cp -a 복사 경로). 다른 노트북은 cp 경로 그대로 — clone → 빌드 시 `ros2 launch cobot2_bringup bringup_all.launch.py` resolve 확인. (이 머신은 검증용 symlink 라 무관.)

3. **[문서] Dockerfile 레이어 재정렬** — `containers/yolo-detection/Dockerfile`: `COPY object_detection` 이 torch pip 레이어보다 앞 → 노드 코드만 고쳐도 torch 재다운로드. 무거운 pip 레이어를 소스 COPY 앞으로. **이미지 재빌드 시 드라이브 tar/SHA256 갱신 동반**(config.sh `*_IMAGE_SHA256` + 재업로드 — 안 하면 fetch 체크섬 불일치로 실패).

4. **[문서] pick_and_place_text/voice spin 버그** — `{detection.py,yolo.py}` 의 `rclpy.spin_once` 재진입 버그 잔존(object_detection 만 spin 수정). **KeyError(`reversed_class_dict[target]`)는 2026-06-10 에 3 copies 전부 `.get()`+미검출로 수정 완료.** 레거시 spin 버그: 동일 패치 vs 레거시화 결정.

5. **[문서] 모델 가중치 중복** — `object_detection/resource/yolov8n_tools_0122.pt`(6.3MB) + `pick_and_place_text/resource/` 동일본. dedup vs pick_and_place_text 레거시화.

6. **[실측] fleet 기존(DONE) 머신 deps 전파** — toolkit 은 이제 install.sh 자동이나 **step3 가 이미 DONE 인 머신엔 미반영** → 수동 `bash resources/nvidia-container-toolkit-install.sh`. 동일 패턴: DSR 패치(`~/dsr_patch_command.txt`), python3-pymodbus. (새 노트북 처음부터 설치면 모두 자동.)

7. **[문서] 미정리 git** — backup 브랜치 `backup/pre-github-sync-2026-05-29`(origin 미push), 태그 `v0.1.0`(미push).

8. **[문서] RealSense udev rule 명시화 패치**(보류) — `realsense-sdk-install.sh` 에 `librealsense2-udev-rules` 명시 + 검증 게이트.

9. **[공통] 브랜치 canonical** — `feat/application-containers` vs `feat/application-shell` → main 병합 시점.

---

## Open Decisions

- nvidia-container-toolkit: 편입 완료(2026-06-09 — install.sh step14, **reboot 이후**; reboot 전 설치가 드라이버 모듈 미로드로 실패해 이동). 잔여: main(host 전용) 병합 시 포함 여부.
- 모델 중복(object_detection vs pick_and_place_text) dedup vs 레거시화.
- pick_and_place_text detection/yolo spin 버그: 동일 패치 vs 레거시화.
- 브랜치 canonical (containers vs shell) — main 병합 대상.
- 미push git 객체(backup 브랜치 / `v0.1.0` 태그).
- RealSense udev 명시화.

---

## Remaining Issues

- pick_and_place_text spin 버그 미수정(robot_control 이 컨테이너 detection 호출로 우회 중).
- fleet 타 머신: DSR 패치 + python3-pymodbus + nvidia-container-toolkit 미반영.
- yolo 이미지 드라이브 다운로드 미실측(4.4GB) — voice 만 실측. 클린설치서 첫 검증.
- **yolo KeyError 수정(2026-06-10)은 소스만 반영 — 이미지 미재빌드라 fetch 시 옛 이미지.** 상단 ⚠ 배너 = 재빌드+드라이브 재업로드 먼저.
- **노출됐던 OPENAI API 키 rotate 권장**(진단 중 터미널 노출). 현재 `.env`(gitignore)에 있고 추적 파일엔 없음(유출 안 됨).

---

## Context Notes

### 이미지 드라이브 배포 (2026-06-09)
- install.sh step14 = `containers/fetch-images.sh`: 공개 구글 드라이브 file ID 로 tar 다운로드 → SHA256 검증 → gz/zip 해제 분기 → `docker load`. 이미지 존재 시 skip(멱등).
- 대용량(>100MB) 다운로드: `drive.usercontent.google.com/download?id=..&export=download` 1차 응답이 virus-scan confirm form(HTML) → `confirm`/`uuid` 토큰 뽑아 2차 요청. 순수 bash curl(host pip 미설치 정책 — gdown 안 씀).
- file ID/SHA256 = `resources/config.sh`(`YOLO/VOICE_IMAGE_GDRIVE_ID`, `_SHA256`). 공개 링크 ID 는 secret 아님. **해시는 레포(신뢰 출처)에, tar 만 드라이브** — 같은 출처면 동시 변조 시 검증 무의미.
- 이미지 제작/검증은 별도 `containers/build-all.sh`(빌드+secret scan+import/tflite smoke). `docker save` tar = yolo 4.3GB / voice 0.42GB(buildkit 레이어 이미 압축 → gzip 무의미). 드라이브 폴더 `1csD1JhZz9xkpBqWR3ZC2udEPeVcndjiI`.
- **클린설치 fetch 실측 주의**: Docker 이미지는 `--reset` 무관 잔존 → 기존 이미지 있으면 step14 skip. 다운로드 경로 타려면 사전 `docker rmi`.

### bringup = cobot2_bringup 패키지 (2026-06-09)
- `ros2 launch cobot2_bringup bringup_all.launch.py mode:=real` — dsr_bringup2 + RealSense(align_depth) + `docker compose up -d` 한 번에. robot_control(실모션·무한루프)은 **미포함** — `ros2 run robot_control robot_control` 분리 실행(인프라/작업 분리). host 기본 `192.168.1.100`(실기 고정), Ctrl+C 시 compose down.
- 레포 경로(compose/config.sh) = config.sh export `ROS2_JAZZY_TEST_REPO`(자기 위치서 계산 — 패키지 설치 후 `__file__` 이 레포 못 가리키는 문제 대응).
- 컨테이너 노드 자동기동: Dockerfile CMD(yolo=`object_detection`, voice=`get_keyword`), compose `command` override 없음 → `up` 만으로 노드 기동(별도 `ros2 run` 불요).
- robot_control voice pick: `DEPTH_OFFSET=-35`, `PLACE_POSITIONS`(pos1/2/3 티칭 posx), `PLACE_LIFT=250`, `PLACE_Z_OFFSET=50`. `/wakeword_detected`(Bool) 토픽으로 wakeword 감지 로깅. `T_gripper2camera.npy` 는 robot_control/resource 에 보유.

### voice 컨테이너 (2026-06-09 검증)
- openwakeword feature 모델(melspectrogram/embedding/silero_vad)을 레포 vendoring(`containers/voice-processing/oww_models/`) + Dockerfile COPY + TFL3 매직 검증 → 빌드 중 다운로드 504 손상본 차단. build-all.sh tflite predict smoke 통과.
- 마이크: host net 은 네트워크만 공유 → `/dev/snd` ALSA 직결(devices) + `group_add: audio`. asound.conf 로 기본 캡처를 실마이크 DMIC `hw:1,6` 고정(컨테이너 기본 `hw:1,0` 은 무음). wakeword/STT 둘 다 sounddevice 16kHz 직접 캡처(scipy resample·PyAudio 폐기).
- 운영 취약: get_keyword 단일스레드 long-blocking → wakeword 대기 중 Ctrl+C 면 좀비 핸들러/백로그. `WAKEWORD_TIMEOUT=30` + 클린 재시작(`docker compose ... down/up voice-processing`)으로 완화.

### 컨테이너 e2e — 검증된 구성 / 함정 (2026-06-08)
- **컨테이너에 cyclonedds RMW 명시 설치 필수** — base 기본 RMW=fastrtps. 없으면 같은 도메인이어도 host 토픽 미발견. yolo/voice Dockerfile runtime 에 `ros-${ROS_DISTRO}-rmw-cyclonedds-cpp`.
- **venv shebang 함정** — colcon build 가 venv 생성 전이라 콘솔스크립트 shebang 이 시스템 python → ultralytics 미발견. `entrypoint.sh` 가 venv site-packages 를 PYTHONPATH 주입해 우회.
- **모델 bake** — `.dockerignore` `**/*.pt` 제외 + `!.../yolov8n_tools_0122.pt` 예외로 이미지 포함.
- **spin 재진입 버그** — 서비스 콜백 내 글로벌 `spin_once` 가 메인 `spin` 과 충돌. ImgNode 전용 `SingleThreadedExecutor`+`spin_once()` 로 해결. import smoke 못 잡음 — service 왕복 e2e 가 잡음.
- nvidia-container-toolkit = host 컴포넌트. passthrough 확인 = `docker run --rm --gpus all ubuntu nvidia-smi`.
- compose voice `env_file: ../.env` → repo 루트 `.env` 존재 필요(빈 파일이라도, gitignore).

### DSR_ROBOT2 jazzy 패치 2종 (origin 반영 완료 — 타 머신/재clone 시 필수)
`dsr_common2/imp/DSR_ROBOT2.py`: ① import NameError `SetSingularityHandlingForce`→`SetSingularHandlingForce`. ② 서비스 무한대기 `_srv_name_prefix=''`→`'dsr_controller2/'`. `dsr-project-install.sh` 가 clone 직후 멱등 sed. DONE 머신은 `~/dsr_patch_command.txt` 직접 sed.

### 실기 로봇 환경 (검증된 값)
- 모델 `m0609`, ns `dsr01`. 컨트롤러 `192.168.1.100:12345`, 그리퍼 toolchanger `192.168.1.1:502`. host `enp4s0 192.168.1.30/24`. 실서버 `/dsr01/dsr_controller2/...`, joint_states `/dsr01/joint_states`.

### RealSense / DDS
- 토픽 `/camera/camera/{color/image_raw, aligned_depth_to_color/image_raw, color/camera_info}`. `align_depth.enable:=true` 필수.
- raw 0Hz → `net.core.rmem_max`(커널)+`SocketReceiveBufferSize`(XML) 둘 다 상향(dds-tuning.sh). `RMW_IMPLEMENTATION`·`CYCLONEDDS_URI` 쉘별 환경변수 — host/컨테이너 일치 필요(`network_mode: host` 상속).

### 함정 (다음 세션 피하기)
- 같은 패턴 버그가 여러 파일에 퍼짐 → 재빌드 전 패키지 전체 grep 전수 수정.
- python stdout block-buffered → hang 오인. `python3 -u` / `flush=True` / `PYTHONUNBUFFERED=1`.
- DSR 서비스 "있는데 응답 없음" → short name(클라) vs `dsr_controller2/` prefix(실서버) 갈림.
- 서비스 `wait_for_service` 무한대기(timeout/break 없음) = 서순엔 강건하나 생산자 영영 부재 시 크래시 아닌 **조용한 hang**. 특히 카메라 미연결/`camera:=false` → object_detection 이 intrinsics 무한 대기 후에야 `/get_3d_position` advertise → robot_control 영영 hang. "멈춤" 디버깅 시 생산자(카메라·실기 컨트롤러) 기동 여부부터 확인.

---

## Current Focus
- **[실측] Top priority**: **다른 노트북(fleet)에서 전체 클린설치 검증** — 새 머신이라 step14 가 드라이브에서 실제 다운로드(yolo 4.4GB 첫 실측), toolkit step3 자동. 드라이브 공유 설정("링크 있는 사람") 확인 필요.
- **[문서]**: Dockerfile 레이어 재정렬(재빌드 시 드라이브 tar/SHA256 갱신 동반).
- **Friction**: 미push git 객체 + 브랜치 canonical + 모델/패키지 중복 정리 결정 대기.
