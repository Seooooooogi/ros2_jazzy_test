# ROS2_Jazzy_Test

- Ubuntu 워크스테이션을 **ROS2 Jazzy 로봇 개발 환경**으로 일관되게 셋업하는 bash 설치 스크립트 모음
- 대상: Ubuntu 24.04 (noble) + NVIDIA GPU 워크스테이션

이 레포는 **base 환경 인스톨러**입니다. cobot2 애플리케이션 소스는 포함하지 않으므로, base 설치 후 cobot2 를 직접 배치하고 `setup-app.sh` 로 워크스페이스·컨테이너를 셋업합니다.

## 설치 순서

```bash
# 1) 저장소 클론 후 디렉토리 진입
git clone https://github.com/Seooooooogi/ros2_jazzy_test.git
cd ros2_jazzy_test

# 2) base 환경 설치 (kernel/NVIDIA/Docker/ROS2 + reboot + VS Code + DDS + 정적 IP + corecode, 10 step)
bash install.sh
```
- 시작 시 confirm 1회, 이후 자동 진행
- step 6 에서 1회 자동 reboot → 로그인 시 GUI autostart 로 자동 재개 (GUI 세션 필요, 복귀 후 sudo 비번 1회)
- autostart 등록 불가 환경이면 reboot 후 `bash install.sh` 재실행 (완료 단계는 자동 skip)
- OPENAI_API_KEY 는 install.sh 가 묻지 않음 — 아래 setup-app.sh(컨테이너 단계)에서 입력

```bash
# 3) cobot2 애플리케이션 소스 배치 — 이 레포는 cobot2 를 제공하지 않는다
mkdir -p ~/cobot_ws/src
cp -a <cobot2-source> ~/cobot_ws/src/cobot2

# 4) 애플리케이션 셋업 — 워크스페이스(DSR 드라이버 + RealSense + cobot2 colcon 빌드)
#    + 컨테이너(toolkit + 이미지 fetch + OPENAI_API_KEY 입력)
bash setup-app.sh
```
- 컨테이너 단계에서 OPENAI_API_KEY 입력 (빈 입력 = skip, 이후 `.env` 직접 편집 가능) — voice 컨테이너가 사용

## 옵션

base 설치 (`install.sh`):

```bash
bash install.sh --status    # 어느 단계까지 끝났는지 상태 출력
bash install.sh --reset     # 설치 상태 초기화 (처음부터 다시)
bash install.sh --verbose   # 각 step 상세 출력을 콘솔에도 표시
bash install.sh --help      # 도움말
```
- 단계별 상세 출력은 레포 루트 `install_log` 에 기록 (`--verbose` 면 콘솔에도)

애플리케이션 (`setup-app.sh`):

```bash
bash setup-app.sh --workspace-only   # 워크스페이스만 (DSR 드라이버 + RealSense + colcon)
bash setup-app.sh --containers-only  # 컨테이너만 (toolkit + 이미지 fetch + OPENAI key)
bash setup-app.sh --reset            # doosan-robot2 재클론 + build/install/log 삭제 후 풀 빌드 (cobot2 보존)
bash setup-app.sh --build            # 컨테이너를 fetch 대신 소스에서 빌드 (cobot2 를 repo cobot_ws/src/cobot2 에 둬야 함)
bash setup-app.sh --help
```

---

## 실행

환경 source (새 터미널마다):

```bash
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
```

### 1) 하나씩 개별 기동

**DSR 드라이버**

```bash
# 실기
ros2 launch dsr_bringup2 dsr_bringup2_rviz.launch.py \
  mode:=real host:=192.168.1.100 port:=12345 model:=m0609 name:=dsr01
# 에뮬레이터
ros2 launch dsr_bringup2 dsr_bringup2_rviz.launch.py \
  mode:=virtual model:=m0609 name:=dsr01
```

**RealSense 카메라**

```bash
ros2 launch realsense2_camera rs_align_depth_launch.py \
  depth_module.depth_profile:=848x480x30 rgb_camera.color_profile:=1280x720x30 \
  align_depth.enable:=true enable_rgbd:=true pointcloud.enable:=true initial_reset:=true
```

**yolo 컨테이너**

```bash
docker compose -f ~/ros2_jazzy_test/containers/docker-compose.yml up -d yolo-detection
```

**voice 컨테이너**

```bash
docker compose -f ~/ros2_jazzy_test/containers/docker-compose.yml up -d voice-processing
docker logs -f voice-processing   # 로그 보기 (Ctrl+C 로 빠져나와도 컨테이너는 계속 실행)
```

**robot_control**

```bash
ros2 run robot_control robot_control   # real / virtual(에뮬레이터) 모두 동작 — RealSense 연결 필요 (virtual 은 실물 로봇 불필요)
```

### 2) 통합 기동

```bash
# 로봇 드라이버 + 카메라 + 컨테이너 (Ctrl+C 로 일괄 정리). 실기=mode:=real / 에뮬레이터=mode:=virtual
bash ~/ros2_jazzy_test/containers/bringup.sh mode:=real
ros2 run robot_control robot_control   # real / virtual(에뮬레이터) 모두 동작 — RealSense 연결 필요 (virtual 은 실물 로봇 불필요)
```
