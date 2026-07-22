# ROS2_Jazzy_Test

- Ubuntu 워크스테이션을 **ROS2 Jazzy 로봇 개발 환경**으로 일관되게 셋업하는 bash 설치 스크립트 모음
- 대상: Ubuntu 24.04 (noble) + NVIDIA GPU 워크스테이션

## 설치 순서

```bash
# 1) 저장소 클론 후 디렉토리 진입
git clone https://github.com/Seooooooogi/ros2_jazzy_test.git
cd ros2_jazzy_test

# 2) base 환경 설치 (kernel/NVIDIA/Docker/ROS2 + reboot + VS Code + DDS + 정적 IP, 9 step)
bash install.sh
```

```bash
# 3) cobot2 애플리케이션 소스 배치
mkdir -p ~/cobot_ws/src ~/cobot_demo_ws/src
cp -a ~/Downloads/cobot2 ~/cobot_ws/src/cobot2

# 3-1) pick & place 실습 패키지는 별도 워크스페이스로 분리
#      (mv 를 건너뛰면 정식 colcon 빌드에 딸려 들어가 동명 패키지와 충돌 — 필수)
mv ~/cobot_ws/src/cobot2/pick_and_place_{text,voice} ~/cobot_demo_ws/src/

# 3-2) voice OPENAI 키 배치 (setup-app.sh 빌드 전!) — voice_processing 노드는 자기 패키지의
#      resource/.env 를 읽고 colcon 빌드에 내장한다. 빌드 전에 넣어야 한 번의 빌드로 반영된다.
#      (별도 안내로 받은 실제 키로 sk-... 를 교체)
echo 'OPENAI_API_KEY=sk-...' \
  > ~/cobot_ws/src/cobot2/voice_processing/resource/.env

# 4) 애플리케이션 셋업 — 워크스페이스(DSR 드라이버 + RealSense + host voice 설치 + cobot2 colcon 빌드)
#    + 컨테이너(toolkit + yolo :dev-builder 이미지 빌드)
bash setup-app.sh
```

> **참고 — voice `.env` 는 빌드 전에 배치.** 노드가 `resource/.env` 를 빌드에 내장해 읽으므로,
> 빌드 후에 추가했거나 키를 바꿨으면 그 패키지만 재빌드해야 반영된다:
> `colcon build --packages-select voice_processing` (이후 `source ~/cobot_ws/install/setup.bash`)

## 옵션

base 설치 (`install.sh`):

```bash
bash install.sh --status    # 어느 단계까지 끝났는지 상태 출력
bash install.sh --reset     # 설치 상태 초기화 (처음부터 다시)
bash install.sh --verbose   # 각 step 상세 출력을 콘솔에도 표시
bash install.sh --no-nvidia-driver  # NVIDIA 드라이버 설치 단계 건너뜀 (드라이버를 이미 별도 설치한 머신용)
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

기동 방식은 두 가지다. 둘 다 같은 launch(`m0609_rg2_bringup`)를 쓴다.

| 방식 | 명령 | 올라오는 것 |
|------|------|------------|
| 개별 기동 | `ros2 launch m0609_rg2_bringup bringup.launch.py` | 로봇 + 그리퍼 + RViz (URDF 에 브라켓·D435 모델 포함 — 카메라 드라이버는 안 뜸) |
| 통합 실행 | `bash containers/bringup.sh` | 위 + RealSense 드라이버 + yolo 컨테이너 + host voice |

**개별 기동 (m0609_rg2_bringup)**

로봇·그리퍼만 확인하거나 컨테이너 없이 RViz 를 보고 싶을 때 쓴다. 기본값
(`mode:=virtual`, `camera:=false`)에서는 **RealSense 드라이버가 뜨지 않는다** — 카메라를
아래 "RealSense 카메라만 따로" 로 별도 터미널에 띄워 붙이는 학습 흐름이 그래서 가능하다.

```bash
# 에뮬레이터 (기본)
ros2 launch m0609_rg2_bringup bringup.launch.py
# 실기
ros2 launch m0609_rg2_bringup bringup.launch.py mode:=real host:=192.168.1.100
# 카메라 드라이버까지
ros2 launch m0609_rg2_bringup bringup.launch.py camera:=true
```

이 패키지는 `setup-app.sh` 가 `${DSR_WORKSPACE}/src` 로 링크해 둔다. **doosan-robot2 가 같은
워크스페이스에 빌드돼 있어야 한다** — 없으면 launch 가 무엇이 빠졌는지 알려주며 멈춘다.
별도 워크스페이스에 이 패키지만 빌드했다면 DSR 이 있는 쪽을 먼저 source 한다:

```bash
source ~/cobot_ws/install/setup.bash        # DSR 제공
source <m0609 워크스페이스>/install/setup.bash
```

**launch 인자**

- `mode:=virtual|real` : 에뮬레이터(기본) vs 실기 컨트롤러.
- `host:=` / `port:=` : 실기 IP·포트. `virtual` 이면 무시되고 `127.0.0.1` 로 강제된다.
- `rt_host:=` : 실기 RT control 채널 IP (기본 `192.168.137.50`).
- `camera:=true|false` : RealSense 드라이버 기동. 기본 `false`, `mode:=real` 이면 항상 기동.
- `rviz:=true|false` : RViz 기동 (기본 `true`).

**DSR 드라이버만 따로 (그리퍼·브라켓 없음)**

드라이버 자체를 격리해서 볼 때만 쓴다. 그리퍼와 브라켓/카메라가 URDF 에 없다.

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

**RealSense 카메라만 따로**

카메라를 별도 터미널에 띄운다. 위 개별 기동에 이걸 붙이면 통합 실행과 **똑같은 토픽**
(`/camera/color/image_raw` 등)이 나오므로, 소비자 노드의 실행 명령을 바꾸지 않아도 된다.

```bash
ros2 run realsense2_camera realsense2_camera_node --ros-args \
  -r __ns:=/ -r __node:=camera \
  -p enable_color:=true -p enable_depth:=true \
  -p depth_module.depth_profile:=848x480x30 -p rgb_camera.color_profile:=1280x720x30 \
  -p align_depth.enable:=true -p enable_rgbd:=true -p enable_sync:=true \
  -p pointcloud.enable:=true -p initial_reset:=true
```

**인자**

- `-r __ns:=/ -r __node:=camera` : **빼면 안 된다.** 이 드라이버는 스트림 토픽을 private(`~/`)로
  만들고 노드 기본 네임스페이스가 upstream 소스에 `/camera` 로 박혀 있어, 아무것도 안 주면
  `/camera/camera/*` 라는 중복 경로가 나온다. 루트(`/`)를 명시해야 통합 기동과 같은 `/camera/*` 가 된다.
- `enable_color` / `enable_depth` : 컬러·깊이 스트림 활성화.
- `depth_module.depth_profile:=848x480x30` : 깊이 스트림 848×480, 30fps.
- `rgb_camera.color_profile:=1280x720x30` : 컬러 스트림 1280×720, 30fps.
- `align_depth.enable:=true` : 깊이 영상을 컬러 카메라 좌표에 정렬(픽셀 대응).
- `enable_rgbd:=true` : RGBD 합성 토픽 발행.
- `enable_sync:=true` : 컬러·깊이 프레임 타임스탬프 동기화.
- `pointcloud.enable:=true` : 3D 포인트클라우드 발행.
- `initial_reset:=true` : 기동 전 카메라 하드웨어 리셋(USB 재연결 꼬임 방지).

> 다른 자료에서 흔히 보이는 `ros2 launch realsense2_camera rs_align_depth_launch.py ...` 는
> upstream 기본값이라 토픽이 `/camera/camera/*` 로 나온다. 그쪽으로 띄웠다면 소비자 remap 을
> `-r img_node:__ns:=/camera/camera` 로 맞춰야 한다.

**학습용 — 카메라를 따로 붙여 보기**

터미널 3개로 통합 실행과 같은 상태를 손으로 만든다.

```bash
# 터미널 1 — 로봇 + 그리퍼 + RViz (카메라 없음)
ros2 launch m0609_rg2_bringup bringup.launch.py

# 터미널 2 — 카메라 (위 ros2 run 명령 그대로)
ros2 run realsense2_camera realsense2_camera_node --ros-args -r __ns:=/ -r __node:=camera ...

# 터미널 3 — 소비자 노드
ros2 topic list | grep '^/camera/'      # /camera/camera/ 가 보이면 터미널 2 의 remap 누락
ros2 run object_detection object_detection --ros-args -r img_node:__ns:=/camera
```

소비자는 절대 경로가 아니라 상대 이름(`color/image_raw` 등)을 구독한다. `img_node:` 접두어 없이
`-r __ns:=/camera` 만 주면 같은 프로세스의 `object_detection_node` 까지 옮겨져 `robot_control` 이
부르는 `/get_3d_position` 이 끊긴다. remap 을 빠뜨리면 에러 없이 토픽만 조용히 빈다.

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

또는 compose 없이 docker run — **최초 1회만** 컨테이너 생성:

```bash
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

이후에는 재사용 (생성 시 명령이 컨테이너에 박혀 있어 start 때마다 clean build → idle 이 다시 실행됨):

```bash
docker start yolo-detection
docker stop yolo-detection
```

`docker rm -f yolo-detection` 후 재생성이 필요한 경우는 **run 플래그(-v/-e/--network/--gpus)를 바꿀 때뿐** — 컨테이너 설정은 생성 시점에 고정이라 기존 컨테이너에서 변경 불가.

```bash
docker logs -f yolo-detection                 # "Summary: N package finished" 뜨면 Ctrl+C
docker exec -it yolo-detection bash
```

**컨테이너 안에서 바꾼 것들은 어떻게 되나**

| 변경 | 보존 | 반영 방법 |
|------|------|----------|
| `/ws/src` 코드 수정 (컨테이너 안/host 어디서든) | 영구 — host bind mount 라 같은 파일. `docker rm` 해도 안 사라짐 | `.py` 수정 → `--symlink-install` 덕에 재빌드 불필요, 노드만 재실행. 파일 추가·`setup.py` 변경 → 컨테이너 안에서 `colcon build --symlink-install --merge-install` 재실행 |
| `apt install` 등 컨테이너 파일시스템 변경 | stop/start 에는 유지, **`docker rm` 시 소실** | 계속 쓸 패키지면 `containers/yolo-detection/Dockerfile` 에 추가 후 이미지 재빌드 (`bash containers/build-all.sh`) — 이미지가 진실 원천 |

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
