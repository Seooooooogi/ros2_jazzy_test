# ros2_jazzy_test

- Ubuntu 워크스테이션을 **ROS2 Jazzy 로봇 개발 환경**으로 일관되게 셋업하는 bash 설치 스크립트 모음
- 구성: NVIDIA 드라이버 + Docker + ROS2 Jazzy + Doosan DSR + RealSense + 음성(LangChain)
- 대상: Ubuntu 24.04 (noble) + NVIDIA GPU 워크스테이션
- 전제: 동일 모델 머신에 반복 설치/검증

## 설치 순서

- 권장 진입점: `install.sh` 하나
- 내부 실행 순서: `a01 → reboot → a02 → a03 → a04` (단일 시퀀스, `[n/total]` 진행률)
- 완료된 단계는 자동 skip

```bash
# 1) 저장소 클론 후 디렉토리 진입
git clone https://github.com/Seooooooogi/ros2_jazzy_test.git ros2_jazzy_test
cd ros2_jazzy_test

# 2) 전체 설치 시작 (a01 단계에서 시스템 준비 후 reboot 필요 가능)
bash install.sh

# 3) reboot 발생 시 부팅 후 같은 명령 재실행 → 멈춘 다음 단계부터 이어서 진행
bash install.sh
```

- **재개 가능(resumable)** — 실패/리부트로 끊겨도 마지막 성공 단계 기록
- 재실행 시 처음이 아니라 다음 단계부터 진행

### 단계 구성

| 단계 | 스크립트 | 내용 |
|------|----------|------|
| a01 | `a01-prerequirements.sh` | 시스템 준비 — 커널 베이스라인, NVIDIA 드라이버, Docker, ROS2 Jazzy. **reboot 포함** |
| a02 | `a02-robot-camera.sh` | Doosan DSR 로봇 + RealSense 카메라 설치 |
| a03 | `a03-vs-code-install.sh` | VS Code 설치 |
| a04 | `a04-voice-precheck.sh` | 음성 처리 사전 점검 (API 키 입력 포함) |

- 각 단계 단독 실행 가능
- `install.sh` 와 상태 파일 공유 → 어느 쪽으로 실행하든 skip 판정 일관

```bash
bash a01-prerequirements.sh   # 시스템 (reboot 포함)
bash a02-robot-camera.sh      # 로봇 + 카메라
bash a03-vs-code-install.sh   # VS Code
bash a04-voice-precheck.sh    # 음성 점검
```

## 자주 쓰는 옵션

```bash
bash install.sh --status   # 어느 단계까지 끝났는지 상태 출력
bash install.sh --reset    # 설치 상태 초기화 (처음부터 다시)
bash install.sh --help     # 도움말
```

- 콘솔 출력: `[n/total]` 진행률 + 경고/에러만
- 단계별 상세 출력(apt/pip/colcon): `~/.ros2_jazzy_test/install.log` 에 append
- 상세 출력 실시간 확인: `VERBOSE=1 bash install.sh`

## 환경 변수 / 시크릿

- 음성 처리용 API 키 등은 `.env` 로 관리
- 템플릿: `.env.example` (복사 후 값 입력)
- `.env` 는 절대 커밋 금지

```bash
cp .env.example .env
# .env 편집해 실제 키 입력
```

## 워크스페이스 (cobot2_ws) 빌드 / 위치

- a02 단계(로봇/카메라): 워크스페이스 **자동 clone + 빌드** — 별도 수동 빌드 불필요
- 기본 위치: `~/cobot2_ws` (환경변수 `DSR_WORKSPACE` 로 변경 가능)
- 구성: `doosan-robot2`(jazzy) clone + host 패키지(`robot_control`, `od_msg`)만 복사 후 `colcon build`
  - app 패키지(`object_detection` / `voice_processing` 등)는 host ws 에 없음 — yolo/voice 컨테이너가 담당
- doosan-robot2(jazzy) 소스 호환 패치(서비스 이름·prefix) a02 에서 자동 적용 → **손수 clone 시 패치 누락으로 런타임 깨짐**

수정 후 재빌드:

```bash
cd ~/cobot2_ws
source /opt/ros/jazzy/setup.bash
colcon build
source install/setup.bash
```

다른 위치(예: 바탕화면)에 두고 빌드 — `DSR_WORKSPACE` 지정 후 a02 실행 (패치 포함 전체 파이프라인이 그 경로에서 수행):

```bash
DSR_WORKSPACE=~/Desktop/cobot2_ws bash a02-robot-camera.sh
# 이후 재빌드도 같은 경로에서: cd ~/Desktop/cobot2_ws && colcon build
```

## 설치 후 실행 — 로봇 · 카메라 (개별 실행)

환경 source (새 터미널마다):

```bash
source /opt/ros/jazzy/setup.bash
source ~/cobot2_ws/install/setup.bash   # overlay (dsr_bringup2 / robot_control 제공)
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a   # RMW(CycloneDDS) / domain
```

로봇 드라이버 (실로봇 — 컨트롤러 IP 지정):

```bash
ros2 launch dsr_bringup2 dsr_bringup2_rviz.launch.py \
  mode:=real host:=<controller-ip> port:=12345 model:=m0609 name:=dsr01
```

- 에뮬레이터로 띄우려면 `mode:=virtual` (컨트롤러 연결 없이)

RealSense 카메라 (검증된 프로파일):

```bash
ros2 launch realsense2_camera rs_align_depth_launch.py \
  depth_module.depth_profile:=848x480x30 rgb_camera.color_profile:=1280x720x30 \
  align_depth.enable:=true enable_rgbd:=true pointcloud.enable:=true initial_reset:=true
```

- `align_depth.enable:=true` 필수 — 없으면 `aligned_depth_to_color` 미publish
