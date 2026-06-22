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
- 단계별 상세 출력은 레포 루트 `install_log` 에 기록 (git 미추적 · 재생성 가능)

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
source ~/cobot_ws/install/setup.bash   # overlay (dsr_bringup2 / robot_control 제공)
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a   # RMW(CycloneDDS) / domain
```

## 컨테이너 노드 개별 실행 (디버깅)

```bash
# 프로덕션 정의 + dev override 를 함께 머지 (cwd 무관 — 절대경로)
DEV="-f $HOME/ros2_jazzy_test/containers/docker-compose.yml -f $HOME/ros2_jazzy_test/containers/docker-compose.dev.yml"
docker compose $DEV build            # 최초 1회 — dev-builder 이미지 (프로덕션 이미지와 분리)
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

- 자세한 dev 모드 설명은 `containers/README.md` 참조.

## robot_control 전체 실행 순서

1. **DSR 드라이버** — 실기 `mode:=real`, 에뮬레이터 `mode:=virtual`

   ```bash
   ros2 launch dsr_bringup2 dsr_bringup2_rviz.launch.py \
     mode:=real host:=192.168.1.100 port:=12345 model:=m0609 name:=dsr01
   ```

2. **RealSense 카메라** (host, `align_depth.enable:=true` 필수)

   ```bash
   ros2 launch realsense2_camera rs_align_depth_launch.py \
     depth_module.depth_profile:=848x480x30 rgb_camera.color_profile:=1280x720x30 \
     align_depth.enable:=true enable_rgbd:=true pointcloud.enable:=true initial_reset:=true
   ```

3. **yolo 노드*

4. **voice 노드**

5. **robot_control** (host — 오케스트레이터, 위 두 서비스 + DSR 의 client)

   ```bash
   ros2 run robot_control robot_control
   ```

> **통합 기동**
>
> ```bash
> ros2 launch cobot2_bringup bringup_all.launch.py mode:=real   # DSR + 카메라 + yolo/voice 컨테이너
> ros2 run robot_control robot_control                          # 인프라 기동 후 별도 터미널
> ```
>
> 프로덕션 컨테이너만 따로 띄우려면: `docker compose -f ~/ros2_jazzy_test/containers/docker-compose.yml up -d` (노드 auto-run · 종료는 `... down`).

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
