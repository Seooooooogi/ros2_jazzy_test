---
name: phase4-container-architecture
description: Phase 4 host/container 분리 아키텍처 확정 결정 3건 (RealSense / robot_control / 통신 방식) + cobot2_ws·corecode 코드 분석 결과. 2026-05-28 확정.
metadata:
  type: project
---

# Phase 4 컨테이너 아키텍처 결정 (2026-05-28)

> 인덱스(MEMORY.md) 미반영 — 병렬 세션 동시 쓰기 충돌 회피 목적의 standalone 파일.
> 옆 세션이 필요하면 이 파일을 직접 Read. 인덱스 등재는 단일 세션 정리 시점에 수행.

배포 환경 코드(`cobot2_ws.zip`, `corecode.zip`)를 분석하고 노션 아키텍처 페이지
("(협동2) Humble→Jazzy 마이그레이션", `36c563918e59805997c4e8e533067303`)를 검증·정정하면서 확정.

## 확정 결정 3건 (사용자, 2026-05-28)

1. **RealSense = host realsense2_camera 노드 publish + yolo 컨테이너 subscribe (옵션 A)**
   - **Why**: 현 코드(`object_detection/realsense.py`)가 이미 `/camera/camera/{color/image_raw, aligned_depth_to_color/image_raw, color/camera_info}` 토픽 subscribe 구조. 코드 무수정.
   - **How to apply**: yolo 컨테이너 deps 에 `pyrealsense2`·USB passthrough **불필요**, `cv_bridge`만 필요. host 가 `ros-jazzy-realsense2-*` + librealsense2 SDK(udev rule 포함) 책임.

2. **robot_control 노드 = host 에 유지 (옵션 A)**
   - **Why**: `robot_control/robot_control.py` 의 `DSR_ROBOT2` API 는 controller 와 TCP 12345(DRFL), `onrobot.py` 의 RG2 gripper 는 Modbus TCP 192.168.1.1:502 로 직접 통신 — 실기 IP 직접 접근이 host 에서 자연.
   - **How to apply**: `~/cobot_ws` colcon 에 빌드(`robot_control`, `pick_and_place_*`, `rokey`, `od_msg`). 컨테이너화 대상 아님.

3. **yolo/voice ↔ robot_control 통신 = 현 ROS2 service 유지 (옵션 A)**
   - **Why**: object_detection 은 `/get_3d_position`(od_msg/SrvDepthPosition) serve, voice 는 `/get_keyword`(std_srvs/Trigger) serve. robot_control 이 service client. request-response 가 pick-and-place trigger 흐름에 적합. 코드 무수정.
   - **How to apply**: 노션 다이어그램에 있던 토픽 `/detect/bbox`·`/voice/text`·`/robot_command` 은 **실재하지 않음** — service 로 표기. 실재 토픽은 `/camera/camera/*` 와 `/dsr01/joint_states` 둘뿐.

→ 이 3건은 세션 핸드오프의 "Phase 4 디자인 결정 (b) ROS2 통신" 중 통신 모델 부분을 구체화. base image / network_mode 는 여전히 ADR 후보.

## 컨테이너 빌드 시 확정/주의 (구현 가능성 검토 결과: GO)

- **RMW + ROS_DOMAIN_ID 완전 일치** (host + 두 컨테이너). Fast-DDS↔CycloneDDS 혼합 시 같은 토픽도 discovery 실패. `network_mode: host` 필수 (Docker bridge 는 DDS multicast forward 안 함).
- **GPU**: `ros:jazzy-ros-base-noble` + pip torch(cuXXX wheel) 로 충분 — torch wheel 이 CUDA runtime 동봉, CUDA base image 불필요. NVIDIA Container Toolkit 만. **컨테이너 CUDA ≠ host CUDA toolkit** → ADR-006(Noble repo 12-4 부재)은 host(DSR/colcon)용, 컨테이너와 독립.
- **od_msg**: yolo 컨테이너가 `/get_3d_position` 제공 위해 컨테이너 안에서 od_msg 빌드 필요. voice 는 std_srvs/Trigger 만 → 커스텀 msg 불필요.
- **Audio**: PulseAudio/PipeWire socket mount + UID 매칭(`user: "1000:1000"`). raw `/dev/snd` 직접 mount 는 host PipeWire 충돌.
- **openwakeword**: `hello_rokey_8332_32.tflite` 를 이미지에 COPY. `download_models()` 호출 없는 cobot2_ws 버전 사용 (corecode 버전은 download 호출함).

## 코드 분석 핵심 사실 (cobot2_ws / corecode)

- **`pick_and_place_voice` 가 마스터 패키지** — `object_detection`/`voice_processing`/`robot_control` 을 한 패키지로 묶고 entry_points 를 거기 정의(`setup.py`). 컨테이너 분리 시 yolo←object_detection / voice←voice_processing / host←robot_control 로 쪼개는 게 실제 Dockerfile·colcon 작업 포인트.
- **데이터 흐름**: 내장 mic→PyAudio→openwakeword(tflite,로컬)→Whisper API(STT)→gpt-4o(langchain)→`/get_keyword` 응답 → robot_control 이 키워드별 `/get_3d_position` 호출 → `T_gripper2camera.npy` 로 camera→base 변환 → movej/movel + RG2.
- **`corecode.zip` = 컨테이너 적재 대상 아님** — 개발/연구용. Calibration_Tutorial(→ `T_gripper2camera.npy` 산출), OD_Tutorial(→ `yolov8n_tools_0122.pt` 산출), VoiceProcessing(standalone 원본), DRL_Tutorial(DSR API 학습 노트북). `onrobot.py`·`realsense.py` 가 cobot2_ws 와 중복 → 단일 source 화 후보.
- **DSR joint state 토픽 변경**: 구 `/dsr01/msg/joint_state`(Float64MultiArray) → 현 `/dsr01/joint_states`(JointState). `rokey/basic/get_current_pos.py` 주석에 2025.12 Doosan 변경 명시.

## 미해결 (사용자 결정 대기)

- **colcon ws 이름 불일치**: 노션 3-1 표는 `~/cobot2_ws/`, 다이어그램·`get_keyword.py:26` 주석은 `~/cobot_ws/`(그 아래 `src/cobot2_ws/`). 표준 명칭 미확정 — 통일 필요.
- **Phase 4 base image ADR**: `ros:jazzy-ros-base-noble`(섹션 3 기재) 로 GPU 가능 확인됨. nvidia/cuda base 는 system CUDA 컴파일 필요 시에만. 정식 ADR 화 여부 미결.

## 노션 페이지 변경 이력 (2026-05-28)

- 1-1 / 2-1 다이어그램: service vs topic 정정 + realsense2_camera·robot_control 노드 추가 + Modbus(502)/DRFL(12345) 채널 명시.
- 2-2 표: 파랑/초록 행 host realsense + service 혼용으로 갱신.
- 섹션 3(타 담당자 작성분): 결정 A 충돌 4곳만 외과적 정정 (yolo deps pyrealsense2→cv_bridge, USB 행 host화, pick_and_place 행 service화, 3-2-6 USB 함정).
