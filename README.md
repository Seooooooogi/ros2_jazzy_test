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

YOLO / Voice 컨테이너:

- 각 컨테이너는 기동과 동시에 노드 자동 실행 (yolo=`object_detection`, voice=`get_keyword`) — 별도 `ros2 run` 불필요
- 전제: 카메라(위 RealSense)가 먼저 떠 있어야 yolo 가 토픽 구독 / voice 는 `.env` 의 `OPENAI_API_KEY` 필요 (cyclonedds 설정은 install.sh 가 렌더)

```bash
# 둘 다 기동
docker compose -f ~/ros2_jazzy_test/containers/docker-compose.yml up -d

# 개별 기동 (서비스명 지정)
docker compose -f ~/ros2_jazzy_test/containers/docker-compose.yml up -d yolo-detection
docker compose -f ~/ros2_jazzy_test/containers/docker-compose.yml up -d voice-processing

# 로그 확인 / 종료
docker compose -f ~/ros2_jazzy_test/containers/docker-compose.yml logs -f
docker compose -f ~/ros2_jazzy_test/containers/docker-compose.yml down
```

## 컨테이너 셸로 직접 들어가기 (bash)

떠 있는 컨테이너 안으로 들어가 토픽 확인·노드 수동 실행 등을 할 수 있다.

```bash
docker exec -it yolo-detection bash      # 또는 voice-processing
```

- 진입한 셸에는 ROS 환경이 자동으로 잡혀 있지 않으므로(entrypoint 는 컨테이너 메인 프로세스 전용), 안에서 직접 source 한다:

  ```bash
  source /opt/ros/jazzy/setup.bash
  source /ws/install/setup.bash          # overlay (od_msg / object_detection / voice_processing)
  ```

- 이후 `ros2 topic list`, `ros2 run object_detection object_detection` 등을 직접 실행한다.
- 코드를 고치며 즉시 반영·디버깅하려면 **개발 모드**(소스 bind-mount, 진입 시 `/ws` 자동 이동, 빌드 산출물 영속)를 쓴다 → `containers/README.md` 참조.

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
