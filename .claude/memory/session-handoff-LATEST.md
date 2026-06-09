# Session Handoff — LATEST

> 매 세션 종료 전 갱신. 글로벌 `SessionStart` hook 이 자동 로드.
> Forward-looking only — 본 세션에서 한 일이 아니라 다음 세션이 할 일.
> 두 머신 공유 — **[실측]** 머신(로봇/카메라 실기) + **[문서]** 머신(git/문서/lessons). 항목에 담당 표기.

## Last updated
2026-06-09 — **[실측/문서]** ① voice 컨테이너 e2e(wakeword→STT→LLM→service `/get_keyword`→실로봇 pick&place + pos1/2/3 목적지 배치) 검증 완료. ② 통합 bringup 을 전용 `cobot2_bringup` 패키지로 분리(robot_control 제외, host IP 192.168.1.100 고정). ③ install.sh step14 를 빌드→**공개 구글 드라이브에서 이미지 tar 받아 docker load**(`fetch-images.sh`)로 전환 — voice fetch 실측 통과. 직전 2026-06-08: YOLO 컨테이너 e2e + 실로봇 pick.

---

## Next Actions (priority order)

1. **[실측] 전체 클린설치 검증** (예정) — `bash install.sh --reset` → `bash install.sh`. **step14 fetch 다운로드 경로를 실측하려면 클린설치 전 `docker rmi local/ros2-jazzy-yolo:dev local/ros2-jazzy-voice:dev`** (이미지 잔존 시 fetch 가 skip — Docker 이미지는 `--reset` 무관 잔존). yolo tar(4.4GB) 드라이브 다운로드는 **미실측**(voice 433MB 만 검증) → 클린설치가 첫 실측. a01(step1~6) NVIDIA+reboot destructive, step12 `.env` OPENAI_API_KEY interactive.

2. **[실측/문서] cobot2_bringup 클린설치 자동 빌드 검증** — `dsr-project-install.sh` HOST_PKGS 에 등록됨(cp -a 복사 경로). 이 머신은 검증용 **symlink**(`~/cobot2_ws/src/cobot2_bringup`→repo)라, 클린설치가 cp 로 재생성하는지 확인.

3. **[문서] 설치 흐름에 nvidia-container-toolkit 편입** — `resources/nvidia-container-toolkit-install.sh`(멱등, host GPU 런타임) 를 `docker-install.sh` 끝에서 호출하도록 편입 + `docs/COMPATIBILITY.md`. toolkit 은 컨테이너 운영 머신만 필요 — main(host 전용)에도 넣을지 결정.

4. **[문서] Dockerfile 레이어 재정렬** — `containers/yolo-detection/Dockerfile`: `COPY object_detection` 이 torch pip 레이어보다 앞 → 노드 코드만 고쳐도 torch 재다운로드. 무거운 pip 레이어를 소스 COPY 앞으로. (이미지 재빌드 시 드라이브 tar/SHA256 갱신 동반 — config.sh + 재업로드.)

5. **[문서] pick_and_place_text spin 버그** — `pick_and_place_text/{detection.py,yolo.py}` 에 `rclpy.spin_once` 재진입 버그 잔존(object_detection 만 수정). 동일 패치 vs 레거시화 결정.

6. **[문서] 모델 가중치 중복** — `object_detection/resource/yolov8n_tools_0122.pt`(6.3MB) + `pick_and_place_text/resource/` 동일본. dedup vs pick_and_place_text 레거시화.

7. **[실측] fleet 머신 deps 전파** — (a) DSR 패치(`~/dsr_patch_command.txt`), (b) **python3-pymodbus**, (c) nvidia-container-toolkit. 공통 원인: DONE step 에 나중에 추가된 패키지는 기존 머신에 미반영.

8. **[문서] 미정리 git** — backup 브랜치 `backup/pre-github-sync-2026-05-29`(origin 미push), 태그 `v0.1.0`(미push).

9. **[문서] RealSense udev rule 명시화 패치**(보류) — `realsense-sdk-install.sh` 에 `librealsense2-udev-rules` 명시 + 검증 게이트.

10. **[공통] 브랜치 canonical** — `feat/application-containers` vs `feat/application-shell` → main 병합 시점.

---

## Open Decisions

- nvidia-container-toolkit: `docker-install.sh` 편입 위치 + main(host 전용)에도 설치할지.
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

---

## Current Focus
- **[실측] Top priority**: 전체 클린설치 검증(step14 드라이브 fetch 실측 — 사전 `docker rmi` 필요, yolo 4.4GB 첫 다운로드).
- **[문서]**: nvidia-container-toolkit `docker-install.sh` 편입(+COMPATIBILITY), Dockerfile 레이어 재정렬.
- **Friction**: 미push git 객체 + 브랜치 canonical + 모델/패키지 중복 정리 결정 대기.
