# ROS2_Jazzy_Test

- Ubuntu 워크스테이션을 **ROS2 Jazzy 로봇 개발 환경**으로 일관되게 셋업하는 bash 설치 스크립트 모음
- 대상: Ubuntu 24.04 (noble) + NVIDIA GPU 워크스테이션

## 설치 순서

```bash
# 1) 저장소 클론 후 디렉토리 진입
git clone https://github.com/Seooooooogi/ros2_jazzy_test.git
cd ros2_jazzy_test

# 2) 전체 설치
bash install.sh
```
- 시작 시 OPENAI_API_KEY + confirm 1회 입력, 이후 자동 진행
- step 6 에서 1회 자동 reboot → 로그인 시 GUI autostart 로 자동 재개 (GUI 세션 필요, 복귀 후 sudo 비번 1회)
- autostart 등록 불가 환경이면 reboot 후 `bash install.sh` 재실행 (완료 단계는 자동 skip)

## 추가 옵션

```bash
bash install.sh --status   # 어느 단계까지 끝났는지 상태 출력
bash install.sh --reset    # 설치 상태 초기화 (처음부터 다시)
bash install.sh --help     # 도움말
```
- 단계별 상세 출력은 레포 루트 `install_log` 에 기록

## 워크스페이스만 다시 설치

워크스페이스 `~/cobot_ws` 만 다시 빌드

```bash
bash reinstall-workspace.sh           # 증분: 레포 소스 재동기화 + colcon 증분 빌드
bash reinstall-workspace.sh --clean   # 전체: doosan-robot2 재클론 + build/install/log 삭제 후 풀 빌드
bash reinstall-workspace.sh --help
```

## 환경 source (host — 새 터미널마다)

```bash
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a   # RMW(CycloneDDS) / domain
```
## 개별 기동 (디버깅)

1. **DSR 드라이버** (`dsr_bringup2`)

   ```bash
   # 실기
   ros2 launch dsr_bringup2 dsr_bringup2_rviz.launch.py \
     mode:=real host:=192.168.1.100 port:=12345 model:=m0609 name:=dsr01
   # 에뮬레이터
   ros2 launch dsr_bringup2 dsr_bringup2_rviz.launch.py \
     mode:=virtual model:=m0609 name:=dsr01
   ```

2. **RealSense 카메라** (host, `align_depth.enable:=true` 필수)

   ```bash
   ros2 launch realsense2_camera rs_align_depth_launch.py \
     depth_module.depth_profile:=848x480x30 rgb_camera.color_profile:=1280x720x30 \
     align_depth.enable:=true enable_rgbd:=true pointcloud.enable:=true initial_reset:=true
   ```

## 컨테이너 노드 개별 실행 (디버깅)

**매 터미널마다 실행**
```bash
DEV="-f $HOME/ros2_jazzy_test/containers/docker-compose.yml -f $HOME/ros2_jazzy_test/containers/docker-compose.dev.yml"
# 최초 1회 실행 — dev-builder 이미지 (프로덕션 이미지와 분리)
docker compose $DEV build
```

**yolo**

```bash
docker compose $DEV up -d yolo-detection
docker exec -it yolo-detection bash          # /ws 로 진입, ROS overlay·venv 자동 source
ros2 run object_detection object_detection   # 수정 → Ctrl+C → 재실행 반복
```

**voice**

```bash
docker compose $DEV up -d voice-processing
docker exec -it voice-processing bash
ros2 run voice_processing get_keyword
```

- (선택, 단독 테스트) → `robot_control` 없이 마이크·wakeword 동작만 확인
```bash
docker exec -it voice-processing bash -ic 'ros2 service call /get_keyword std_srvs/srv/Trigger "{}"'
```

## 통합 실행 — real / virtual 모드

### real mode (실기)

```bash
ros2 launch cobot2_bringup bringup_all.launch.py mode:=real   # 실기 + 카메라 + production 컨테이너(노드 auto-run, 이미지 사전빌드 필요)
ros2 run robot_control robot_control                          # 별도 터미널: pick & place
```

### virtual mode (에뮬레이터)

```bash
ros2 launch cobot2_bringup bringup_all.launch.py mode:=virtual   # 에뮬레이터 + 카메라 + production 컨테이너(노드 auto-run)
ros2 run robot_control robot_control                             # 별도 터미널: pick & place
```

### robot_control (host)

```bash
ros2 run robot_control robot_control
```

## 시각화 (선택) — 실시간 카메라 + YOLO + 음성 상태

RealSense 화면에 YOLO 실시간 박스·클래스 + 좌상단 wakeword/target/pos 를 겹쳐 띄우는 관찰용 창

```bash
# 1) 추론 컨테이너 — 박스만 /yolo/detections 로 publish
docker compose -f ~/ros2_jazzy_test/containers/docker-compose.yml --profile viz up -d yolo-viz

# 2) host 뷰어 창 (q 로 종료)
source /opt/ros/jazzy/setup.bash
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
python3 ~/ros2_jazzy_test/viz/viewer.py
```
