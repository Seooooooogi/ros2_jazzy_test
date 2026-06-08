# Session Handoff — LATEST

> 매 세션 종료 전 갱신. 글로벌 `SessionStart` hook 이 자동 로드.
> Forward-looking only — 본 세션에서 한 일이 아니라 다음 세션이 할 일.
> 두 머신 공유 — **[실측]** 머신(로봇/카메라 실기) + **[문서]** 머신(git/문서/lessons). 항목에 담당 표기.

## Last updated
2026-06-08 — **[실측]** YOLO 컨테이너 e2e 전 구간 + 실로봇 pick 검증 완료(빌드·GPU·cyclonedds discovery·`/get_3d_position` 검출 → robot_move 실모션 → hammer 그립). 컨테이너/검출노드/로봇 수정 다수 커밋·push. 직전 2026-06-05: CycloneDDS 전환 + bringup launch.

---

## Next Actions (priority order)

1. **[문서] 설치 흐름에 nvidia-container-toolkit 편입** — 오늘 `resources/nvidia-container-toolkit-install.sh` 모듈 신규(멱등, host GPU 런타임). `docker-install.sh` 끝에서 호출하도록 편입 + `docs/COMPATIBILITY.md` 갱신. 단 toolkit 은 컨테이너 운영 머신만 필요 — main(host 전용)에도 넣을지 결정.

2. **[실측/문서] voice 컨테이너 빌드 실패 해결** — `bash containers/build-all.sh` [5/5] voice smoke 실패: openwakeword `melspectrogram.tflite` 손상(`identifier 'l><b' should be 'TFL3'` = 다운로드가 .tflite 아닌 HTML/LFS 포인터). 빌드 중 다운로드라 재현. 모델 pin/mirror/mount 필요. **yolo 무관(통과).** install.sh step14(build-all.sh)가 voice 에서 실패 → dev 통합 설치도 여기서 막힘.

3. **[문서] Dockerfile 레이어 재정렬** — `containers/yolo-detection/Dockerfile`: `COPY object_detection` 이 torch pip 레이어보다 앞 → 노드 코드만 고쳐도 torch(수백MB~GB) 재다운로드. 무거운 pip 레이어를 소스 COPY 앞으로.

4. **[문서] pick_and_place_text spin 버그** — `pick_and_place_text/{detection.py,yolo.py}` 에 동일한 `rclpy.spin_once` 재진입 버그 잔존(오늘 object_detection 만 수정). 그 detection 노드 쓰면 크래시. 오늘 pick 은 robot_move(클라이언트)가 컨테이너 detection 을 호출해 우회. 동일 패치 vs 레거시화 결정.

5. **[문서] 모델 가중치 중복** — bake 결정으로 `object_detection/resource/yolov8n_tools_0122.pt`(6.3MB) 추적 추가. `pick_and_place_text/resource/` 에도 동일본(6.3MB×2). dedup vs pick_and_place_text 레거시화.

6. **[실측] fleet 머신 deps 전파** — (a) DSR 패치(`~/dsr_patch_command.txt`), (b) **python3-pymodbus**(그리퍼) — `dsr-project-install.sh` 에 있으나 a02 가 DONE 인 머신은 skip → 수동 `sudo apt install python3-pymodbus`, (c) nvidia-container-toolkit. 공통 원인: **DONE step 에 나중에 추가된 패키지는 기존 머신에 미반영**.

7. **[문서] 미정리 git** — backup 브랜치 `backup/pre-github-sync-2026-05-29`(origin 미push), 태그 `v0.1.0`(미push), `.gitignore` 에이전트 산출물 4줄 처리 결정.

8. **[문서] RealSense udev rule 명시화 패치**(보류) — `realsense-sdk-install.sh` 에 `librealsense2-udev-rules` 명시 + 검증 게이트. 현재 Recommends 의존이라 `--no-install-recommends` 환경서 silent 누락 가능. 적용 시 `docs/COMPATIBILITY.md` 동반.

9. **[공통] 브랜치 canonical** — `feat/application-containers` vs `feat/application-shell` → main 병합 시점.

---

## Open Decisions

- nvidia-container-toolkit: `docker-install.sh` 편입 위치 + main(host 전용)에도 설치할지(dev-only vs 공통).
- voice 컨테이너 tflite 손상: 모델 pin/mirror/mount 방식.
- 모델 중복(object_detection vs pick_and_place_text) dedup vs 레거시화.
- pick_and_place_text detection/yolo spin 버그: 동일 패치 vs 레거시화.
- 브랜치 canonical (containers vs shell) — main 병합 대상.
- 미push git 객체(backup 브랜치 / `v0.1.0` 태그), `.gitignore` 에이전트 산출물.
- RealSense udev 명시화.

---

## Remaining Issues

- voice 컨테이너 빌드 실패(openwakeword `melspectrogram.tflite` 손상) — yolo 무관.
- pick_and_place_text spin 버그 미수정(robot_move 가 컨테이너 detection 호출로 우회 중).
- fleet 타 머신: DSR 패치 + python3-pymodbus + nvidia-container-toolkit 미반영.

---

## Context Notes

### 컨테이너 e2e — 검증된 구성 / 함정 (2026-06-08)
- yolo `containers:=true` 경로 실동작: 빌드 → GPU(`torch.cuda.is_available()`=True) → host 카메라 cyclonedds discovery → `/get_3d_position` 검출(hammer z=381mm).
- **컨테이너에 cyclonedds RMW 명시 설치 필수** — base `ros-base` 기본 RMW 는 fastrtps. 없으면 런타임 RMW 로드 실패 → 같은 도메인이어도 host 토픽 미발견. yolo/voice Dockerfile runtime 에 `ros-${ROS_DISTRO}-rmw-cyclonedds-cpp` 추가(host colcon-build.sh cyclonedds 핫픽스의 컨테이너 판).
- **venv shebang 함정** — colcon build 가 venv 생성 전이라 ament 콘솔스크립트 shebang 이 시스템 python(`/usr/bin/python3`) → venv 의 ultralytics 미발견(`ros2 run` 시 ModuleNotFoundError). `entrypoint.sh` 가 venv site-packages 를 PYTHONPATH 에 주입해 우회(yolo/voice 공용). 근본해결은 Dockerfile 에서 colcon 을 venv 활성 후로 이동.
- **모델 bake** — `.dockerignore` `**/*.pt` 가 .pt 를 빌드 컨텍스트에서 제외 → `!cobot2_ws/object_detection/resource/yolov8n_tools_0122.pt` 예외로 이미지 포함.
- **spin 재진입 버그** — 서비스 콜백 안에서 `rclpy.spin_once(img_node)`(글로벌) 호출이 메인 `rclpy.spin(node)` 과 충돌("Executor is already spinning"). ImgNode 가 전용 `SingleThreadedExecutor` + `spin_once()` 소유하게 해 해결(detection/yolo/realsense). **빌드 import smoke 는 못 잡음 — service 왕복 e2e 가 잡음.**
- nvidia-container-toolkit = **host 컴포넌트**(컨테이너 아님). 컨테이너 CUDA 는 PyTorch wheel 번들, toolkit 이 host GPU 주입. passthrough 확인 = `docker run --rm --gpus all ubuntu nvidia-smi`.
- compose 의 voice `env_file: ../.env` 때문에 yolo 만 다뤄도 repo 루트 `.env` 존재 필요(없으면 `docker compose exec` 까지 실패). 빈 `.env`(gitignore) 로 충분.

### 실로봇 pick (2026-06-08 검증)
- `pick_and_place_text/robot_move`(host) → 컨테이너 `/get_3d_position` 호출 → `T_gripper2camera.npy` base 변환 → `movel`+그리퍼. hammer 그립 성공.
- **DEPTH_OFFSET = -25**(`robot_move.py`, 원래 -5) — 그리퍼가 ~2cm 위에서 멈춰 더 내림. vel/acc=60.
- robot_move.py 리소스 패키지명 버그 수정(`pick_and_place_voice`→`pick_and_place_text` — voice 안 빌드해도 자기 보정행렬 로드).
- pick_and_place_text host 빌드: 레포 복사 후 `colcon build --packages-select pick_and_place_text`. **python3-pymodbus**(그리퍼 Modbus) 필요. onrobot 은 pymodbus 3.x API.

### DSR_ROBOT2 jazzy 패치 2종 (재발/타 머신 시 필수 — origin 반영 완료)
doosan-robot2 `-b jazzy` clone 의 `dsr_common2/imp/DSR_ROBOT2.py` 이름 불일치:
1. **import NameError**: `SetSingularityHandlingForce`(코드) ↔ `SetSingularHandlingForce`(빌드 클래스) 치환.
2. **서비스 무한 대기**: `_srv_name_prefix=''` → 죽은 이름 `/dsr01/aux_control/...` 호출. prefix `''`→`'dsr_controller2/'`(모듈 레벨).
- `dsr-project-install.sh` 가 clone 직후 멱등 sed. 이미 DONE 머신은 skip → `~/dsr_patch_command.txt` 직접 sed.

### 실기 로봇 환경 (검증된 값)
- 모델 `m0609`, 네임스페이스 `dsr01`. 컨트롤러(DRCF) `192.168.1.100:12345`, 그리퍼 toolchanger `192.168.1.1:502`.
- host `enp4s0 192.168.1.30/24`(로봇망). 실서버 전부 `/dsr01/dsr_controller2/...`, joint_states `/dsr01/joint_states`.

### RealSense / DDS 수신 튜닝
- 카메라 토픽 = `/camera/camera/{color/image_raw, aligned_depth_to_color/image_raw, color/camera_info}`. 기동 시 `align_depth.enable:=true` 필수(없으면 aligned_depth 미publish → depth 계산 실패).
- 대용량 토픽 `ros2 topic hz` 저수치 = 측정/전송 artifact. CycloneDDS raw 0Hz → `net.core.rmem_max`(커널) + `SocketReceiveBufferSize`(XML) **둘 다** 상향. 버퍼 하한 = 최대 토픽 1프레임(pointcloud≈14.7MB).
- `RMW_IMPLEMENTATION`·`CYCLONEDDS_URI` 는 **쉘별 환경변수** — host 노드/측정 터미널·컨테이너(compose environment) 양쪽 일치 필요. `network_mode: host` 라 컨테이너가 host 커널버퍼·NIC whitelist 상속.

### 함정 (다음 세션 피하기)
- 같은 패턴 버그가 패키지 여러 파일에 퍼졌을 때 한 파일만 고치고 (비싼) 재빌드하면 나머지에서 또 터짐 → **빌드 전 패키지 전체 grep 으로 전수 수정**.
- python stdout 파이프 시 block-buffered → hang 오인. `python3 -u` + `flush=True`.
- DSR 서비스 "있는데 응답 없음" → short name(클라이언트) vs `dsr_controller2/` prefix(실서버) 갈림.

---

## Current Focus
- **[문서] Top priority**: voice 컨테이너 tflite 손상 해결 + nvidia-container-toolkit 의 `docker-install.sh` 편입(+COMPATIBILITY).
- **[실측]**: 컨테이너+실로봇 pick 검증 완료. 다음은 멀티타깃 반복 / voice 통합(마이크 passthrough).
- **Friction**: 미push git 객체 + 브랜치 canonical + 모델/패키지 중복 정리 결정 대기.
