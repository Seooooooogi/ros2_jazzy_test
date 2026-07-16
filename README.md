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
mv ~/cobot_ws/src/cobot2/pick_and_place_{text,voice} ~/cobot_demo_ws/src/
rm -f ~/cobot_demo_ws/src/pick_and_place_*/COLCON_IGNORE

# 3-2) voice OPENAI 키 배치
echo 'OPENAI_API_KEY=sk-...' \
  > ~/cobot_ws/src/cobot2/voice_processing/resource/.env

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
bash setup-app.sh                    # 기본: :dev-builder 컨테이너 이미지를 소스에서 빌드
bash setup-app.sh --workspace-only   # 워크스페이스만
bash setup-app.sh --containers-only  # 컨테이너만
bash setup-app.sh --reset            # doosan-robot2 재클론 + build/install/log 삭제 후 풀 빌드
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

**RealSense 카메라**

```bash
ros2 launch realsense2_camera rs_align_depth_launch.py \
  depth_module.depth_profile:=848x480x30 rgb_camera.color_profile:=1280x720x30 \
  align_depth.enable:=true enable_rgbd:=true pointcloud.enable:=true initial_reset:=true
```

**통합 실행 (권장)**

```bash
bash containers/bringup.sh                 # virtual(emulator) + camera + yolo 컨테이너 + host voice (노드까지 자동 기동)
bash containers/bringup.sh mode:=real      # real robot
```

**yolo 컨테이너**

컨테이너 생성 — **최초 1회만**:


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

**robot_control**

```bash
ros2 run robot_control robot_control   # real / virtual(에뮬레이터) 모두 동작 — RealSense 연결 필요 (virtual 은 실물 로봇 불필요)
```

**host voice 노드** 

```bash
ros2 run voice_processing get_keyword               # Ctrl+C → .py 수정 → 재실행
```

```bash
ros2 service call /get_keyword std_srvs/srv/Trigger "{}"
# 응답 예: success=true, message='hammer / pos1' (도구 / 목적지)
```
