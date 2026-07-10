# ROS2_Jazzy_Test

- Ubuntu 워크스테이션을 **ROS2 Jazzy 로봇 개발 환경**으로 일관되게 셋업하는 bash 설치 스크립트 모음
- 대상: Ubuntu 24.04 (noble) + NVIDIA GPU 워크스테이션

## 설치 순서

```bash
# 1) 저장소 클론 후 디렉토리 진입
git clone https://github.com/Seooooooogi/ros2_jazzy_test.git
cd ros2_jazzy_test

# 2) base 환경 설치 (kernel/NVIDIA/Docker/ROS2 + reboot + VS Code + DDS + 정적 IP + corecode 확인, 10 step)
bash install.sh
```

```bash
# 3) cobot2 애플리케이션 소스 배치
mkdir -p ~/cobot_ws/src ~/cobot_demo_ws/src
cp -a ~/Downloads/cobot2 ~/cobot_ws/src/cobot2

# 3-1) pick & place 실습 패키지는 별도 워크스페이스로 분리
mv ~/cobot_ws/src/cobot2/pick_and_place_{text,voice} ~/cobot_demo_ws/src/
rm -f ~/cobot_demo_ws/src/pick_and_place_*/COLCON_IGNORE

# 4) 애플리케이션 셋업 — 워크스페이스(DSR 드라이버 + RealSense + host voice 설치 + cobot2 colcon 빌드)
#    + 컨테이너(toolkit + yolo :dev-builder 이미지 빌드)
bash setup-app.sh
```

## 옵션

base 설치 (`install.sh`):

```bash
bash install.sh --status    # 어느 단계까지 끝났는지 상태 출력
bash install.sh --reset     # 설치 상태 초기화 (처음부터 다시)
bash install.sh --verbose   # 각 step 상세 출력을 콘솔에도 표시
bash install.sh --help      # 도움말
```

애플리케이션 (`setup-app.sh`):

```bash
bash setup-app.sh                    # 기본: :dev-builder 컨테이너 이미지를 소스에서 빌드 (cobot2 템플릿을 수정해 개발하는 수업 흐름)
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
source ~/cobot_ws/install/setup.bash
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
```

> 💡 **매번 치기 싫으면 `~/.bashrc` 에 1회 등록**
> ```bash
> # >>> ros2_jazzy_test runtime env >>>
> [ -f ~/cobot_ws/install/setup.bash ] && source ~/cobot_ws/install/setup.bash
> set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
> # <<< ros2_jazzy_test runtime env <<<
> ```

### 기동

**DSR 드라이버**

```bash
# 실기
ros2 launch dsr_bringup2 dsr_bringup2_rviz.launch.py \
  mode:=real host:=192.168.1.100 port:=12345 model:=m0609 name:=dsr01
# 에뮬레이터
ros2 launch dsr_bringup2 dsr_bringup2_rviz.launch.py \
  mode:=virtual model:=m0609 name:=dsr01
```

**launch 인자**

- `mode:=real|virtual` : 실물 로봇(`real`) vs 에뮬레이터(`virtual`).
- `host:=` / `port:=` : 로봇 컨트롤러 IP·포트 (`real` 에서만 필요; `virtual` 은 생략).
- `model:=m0609` : 로봇 모델명 (Doosan M0609).
- `name:=dsr01` : ROS 네임스페이스 접두어 (토픽·노드 이름 앞에 붙음).

**RealSense 카메라**

```bash
ros2 launch realsense2_camera rs_align_depth_launch.py \
  depth_module.depth_profile:=848x480x30 rgb_camera.color_profile:=1280x720x30 \
  align_depth.enable:=true enable_rgbd:=true pointcloud.enable:=true initial_reset:=true
```

**launch 인자**

- `depth_module.depth_profile:=848x480x30` : 깊이 스트림 848×480, 30fps.
- `rgb_camera.color_profile:=1280x720x30` : 컬러 스트림 1280×720, 30fps.
- `align_depth.enable:=true` : 깊이 영상을 컬러 카메라 좌표에 정렬(픽셀 대응).
- `enable_rgbd:=true` : RGBD 합성 토픽 발행.
- `pointcloud.enable:=true` : 3D 포인트클라우드 발행.
- `initial_reset:=true` : 기동 전 카메라 하드웨어 리셋(USB 재연결 꼬임 방지).

**통합 실행 (권장)**

```bash
bash containers/bringup.sh                 # virtual(emulator) + camera + yolo 컨테이너 + host voice (노드까지 자동 기동)
bash containers/bringup.sh mode:=real      # real robot
```

**yolo 컨테이너**

기동 (compose):

```bash
DEV="-f $HOME/ros2_jazzy_test/containers/docker-compose.yml -f $HOME/ros2_jazzy_test/containers/docker-compose.dev.yml"
docker compose $DEV up -d yolo-detection      # 기동 시 clean colcon build 후 idle
```

또는 compose 없이 docker run:

```bash
docker rm -f yolo-detection 2>/dev/null || true
docker run -d --name yolo-detection \
  --network host -w /ws --gpus all \
  -e ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-0} -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
  -e CYCLONEDDS_URI=file:///cyclonedds.xml -e PYTHONUNBUFFERED=1 \
  -v ~/.config/cyclonedds/cyclonedds.xml:/cyclonedds.xml:ro \
  -v ~/cobot_ws/src/cobot2/yolo_container:/ws/src \
  -v yolo_build:/ws/build -v yolo_install:/ws/install \
  -v ~/ros2_jazzy_test/containers/dev/bashrc:/root/.bashrc:ro \
  local/ros2-jazzy-yolo:dev-builder \
  bash -c 'set +u; source /opt/ros/$ROS_DISTRO/setup.bash; find /ws/build /ws/install -mindepth 1 -delete 2>/dev/null || true; colcon build --symlink-install --merge-install; sleep infinity'
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

```bash
source /opt/ros/jazzy/setup.bash
# ROS_DOMAIN_ID 는 bashrc 에 직접 넣은 값이 이미 셸에 있음(미설정 시 0). 여기서 다시 export 하지 않는다 —
# 컨테이너·host 가 같은 값이면 자동 매칭. 값을 확인만: echo $ROS_DOMAIN_ID
ros2 service call /get_keyword std_srvs/srv/Trigger "{}"
# 응답 예: success=true, message='hammer / pos1' (도구 / 목적지)
```

**플래그 해설**

- `ros2 service call <service> <type> "<payload>"` : 서비스를 1회 호출. `/get_keyword`=서비스명, `std_srvs/srv/Trigger`=서비스 타입, `"{}"`=빈 요청(Trigger 는 입력 필드가 없음).

**robot_control**

```bash
ros2 run robot_control robot_control   # real / virtual(에뮬레이터) 모두 동작 — RealSense 연결 필요 (virtual 은 실물 로봇 불필요)
```
