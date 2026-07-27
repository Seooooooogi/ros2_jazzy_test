# ROS2_Jazzy_Test

- Ubuntu 워크스테이션을 **ROS2 Jazzy 로봇 개발 환경**으로 일관되게 셋업하는 bash 설치 스크립트 모음
- 대상: Ubuntu 24.04 (noble) + NVIDIA GPU 워크스테이션

## 설치 순서

```bash
# 1) 저장소 클론 후 디렉토리 진입
git clone https://github.com/Seooooooogi/ros2_jazzy_test.git
cd ros2_jazzy_test

# 2) base 환경 설치
bash install.sh
```

```bash
# 3) cobot2 애플리케이션 소스 배치
mkdir -p ~/cobot2_ws/src ~/cobot_demo_ws/src
cp -a ~/Downloads/cobot2 ~/cobot2_ws/src/cobot2

# 3-1) pick & place 실습 패키지는 별도 워크스페이스로 분리
mv ~/cobot2_ws/src/cobot2/pick_and_place_{text,voice} ~/cobot_demo_ws/src/

# 3-2) voice OPENAI 키 배치
echo 'OPENAI_API_KEY=sk-...' \
  > ~/cobot2_ws/src/cobot2/voice_processing/resource/.env

# 4) 애플리케이션 셋업 — 워크스페이스
bash setup-app.sh
```

> 워크스페이스 이름이 `~/cobot_ws` → `~/cobot2_ws` 로 바뀌었다. 옛 이름으로 이미 빌드해 둔 머신은
> `export DSR_WORKSPACE="$HOME/cobot_ws"` 로 기존 경로를 계속 쓰거나, 새 경로에서 다시 빌드한다
> (colcon `install/` 에는 절대 경로가 박혀 있어 디렉토리 rename 만으로는 오버레이가 깨진다).

## 옵션

base 설치 (`install.sh`):

```bash
bash install.sh --status    # 어느 단계까지 끝났는지 상태 출력
bash install.sh --reset     # 설치 상태 초기화 (처음부터 다시)
bash install.sh --verbose   # 각 step 상세 출력을 콘솔에도 표시
bash install.sh --no-nvidia-driver  # NVIDIA 드라이버 설치 단계 생략 (개인 노트북 옵션)
bash install.sh --help      # 도움말
```

애플리케이션 (`setup-app.sh`):

```bash
bash setup-app.sh                    
bash setup-app.sh --workspace-only   # 워크스페이스만 (DSR + RealSense + host voice + colcon)
bash setup-app.sh --containers-only  # 컨테이너만 (toolkit + yolo 이미지 빌드)
bash setup-app.sh --reset            # doosan-robot2 재클론 + build/install/log 삭제 후 풀 빌드 (cobot2 보존)
bash setup-app.sh --help
```

---

## 실행

환경 source. 매 터미널마다 아래를 실행:

```bash
source /opt/ros/jazzy/setup.bash
source ~/cobot2_ws/install/setup.bash
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
```

> 💡 **매번 치기 싫으면 `~/.bashrc` 에 1회 등록**
> ```bash
> # >>> ros2_jazzy_test runtime env >>>
> [ -f ~/cobot2_ws/install/setup.bash ] && source ~/cobot2_ws/install/setup.bash
> set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
> # <<< ros2_jazzy_test runtime env <<<
> ```

### 기동

**개별 기동**

```bash
# 에뮬레이터 (기본)
ros2 launch m0609_rg2_bringup bringup.launch.py
# 실기
ros2 launch m0609_rg2_bringup bringup.launch.py mode:=real host:=192.168.1.100
# 카메라 드라이버까지
ros2 launch m0609_rg2_bringup bringup.launch.py camera:=true
```

**RealSense 카메라**

```bash
ros2 run realsense2_camera realsense2_camera_node --ros-args \
  -r __ns:=/ -r __node:=camera \
  -p enable_color:=true -p enable_depth:=true \
  -p depth_module.depth_profile:=848x480x30 -p rgb_camera.color_profile:=1280x720x30 \
  -p align_depth.enable:=true -p enable_rgbd:=true -p enable_sync:=true \
  -p pointcloud.enable:=false -p initial_reset:=true
```

**통합 실행**

```bash
bash containers/bringup.sh                 # virtual(emulator) + camera + yolo 컨테이너 + host voice (노드까지 자동 기동)
bash containers/bringup.sh mode:=real      # real robot
```

**yolo 컨테이너**

1. compose 기동:

```bash
DEV="-f $HOME/ros2_jazzy_test/containers/docker-compose.yml -f $HOME/ros2_jazzy_test/containers/docker-compose.dev.yml"
docker compose $DEV up -d yolo-detection      # 기동 시 clean colcon build 후 idle
```

2. docker run을 통한 컨테이너 생성 — **최초 1회만** :

```bash
docker run -d --name yolo-detection \
  --network host -w /ws --gpus all \
  -e ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-0} -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
  -e CYCLONEDDS_URI=file:///cyclonedds.xml -e PYTHONUNBUFFERED=1 \
  -v ~/.config/cyclonedds/cyclonedds.xml:/cyclonedds.xml:ro \
  -v ~/cobot2_ws/src/cobot2/yolo_container:/ws/src \
  -v yolo_build:/ws/build -v yolo_install:/ws/install \
  -v ~/ros2_jazzy_test/containers/dev/bashrc:/root/.bashrc:ro \
  local/ros2-jazzy-yolo:dev-builder \
  bash -c 'set +u; source /opt/ros/$ROS_DISTRO/setup.bash; find /ws/build /ws/install -mindepth 1 -delete 2>/dev/null || true; colcon build --symlink-install --merge-install; sleep infinity'
```

이후에는 재사용:

```bash
docker start yolo-detection
docker stop yolo-detection
```

```bash
docker logs -f yolo-detection                 # "Summary: N package finished" 뜨면 Ctrl+C
docker exec -it yolo-detection bash
```

컨테이너 안에서 노드 실행:

```bash
ros2 run object_detection object_detection    # Ctrl+C → host 에서 .py 수정 → 재실행
```

**host voice 노드** 

```bash
ros2 run voice_processing get_keyword               # Ctrl+C → .py 수정 → 재실행
```

테스트용 서비스

```bash
source /opt/ros/jazzy/setup.bash
# ROS_DOMAIN_ID 는 bashrc 에 직접 넣은 값이 이미 셸에 있음(미설정 시 0). 여기서 다시 export 하지 않는다 —
# 컨테이너·host 가 같은 값이면 자동 매칭. 값을 확인만: echo $ROS_DOMAIN_ID
ros2 service call /get_keyword std_srvs/srv/Trigger "{}"
# 응답 예: success=true, message='hammer / pos1' (도구 / 목적지)
```

**robot_control**

```bash
ros2 run robot_control robot_control   # real / virtual(에뮬레이터) 모두 동작 — RealSense 연결 필요 (virtual 은 실물 로봇 불필요)
```
