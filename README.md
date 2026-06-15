- Ubuntu 워크스테이션을 **ROS2 Jazzy 로봇 개발 환경**으로 일관되게 셋업하는 bash 설치 스크립트 모음
- 대상: Ubuntu 24.04 (noble) + NVIDIA GPU 워크스테이션

## 설치 순서

```bash
# 1) 저장소 클론 후 디렉토리 진입
git clone https://github.com/Seooooooogi/ros2_jazzy_test.git
cd ros2_jazzy_test

# 2) 전체 설치
bash install.sh --unattended
```

## 추가 옵션

```bash
bash install.sh --status   # 어느 단계까지 끝났는지 상태 출력
bash install.sh --reset    # 설치 상태 초기화 (처음부터 다시)
bash install.sh --help     # 도움말
```

- 콘솔 출력: `[n/total]` 진행률 + 경고/에러만
- 단계별 상세 출력은 `~/.ros2_jazzy_test/install.log` 에 기록

## 설치 후 실행 — 로봇 · 카메라

환경 source (새 터미널마다):

```bash
source /opt/ros/jazzy/setup.bash
source ~/cobot2_ws/install/setup.bash   # overlay (dsr_bringup2 / robot_control 제공)
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a   # RMW(CycloneDDS) / domain
```


DSR + RealSense + yolo/voice 통합 bringup:

```bash
ros2 launch cobot2_bringup bringup_all.launch.py mode:=real
```

## 개별 기동

DSR m0609:

```bash
ros2 launch dsr_bringup2 dsr_bringup2_rviz.launch.py \
  mode:=real host:=192.168.1.100 port:=12345 model:=m0609 name:=dsr01
```

RealSense 카메라:

```bash
ros2 launch realsense2_camera rs_align_depth_launch.py \
  depth_module.depth_profile:=848x480x30 rgb_camera.color_profile:=1280x720x30 \
  align_depth.enable:=true enable_rgbd:=true pointcloud.enable:=true initial_reset:=true
```
## 시각화 (선택) — 실시간 카메라 + YOLO + 음성 상태

RealSense 화면에 YOLO 실시간 박스·클래스 + 좌상단 wakeword/target/pos 를 겹쳐 띄우는 관찰용 창. 위에서 카메라가 떠 있어야 한다.

```bash
# 1) 추론 컨테이너 — 박스만 /yolo/detections 로 publish
docker compose -f ~/ros2_jazzy_test/containers/docker-compose.yml --profile viz up -d yolo-viz

# 2) host 뷰어 창 (q 로 종료)
source /opt/ros/jazzy/setup.bash
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
python3 ~/ros2_jazzy_test/viz/viewer.py
```
