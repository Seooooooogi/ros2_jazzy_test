# ROS2_Jazzy_Test

- Ubuntu 워크스테이션을 **ROS2 Jazzy 로봇 개발 환경**으로 일관되게 셋업하는 bash 설치 스크립트 모음
- 대상: Ubuntu 24.04 (noble) + NVIDIA GPU 워크스테이션

## 설치 순서

```bash
# 1) 저장소 클론 후 디렉토리 진입
git clone https://github.com/Seooooooogi/ros2_jazzy_test.git
cd ros2_jazzy_test

# 2) base 환경 설치 (kernel/NVIDIA/Docker/ROS2 + reboot + VS Code + DDS + 정적 IP + corecode, 10 step)
bash install.sh
```

```bash
# 3) cobot2 애플리케이션 소스 배치
mkdir -p ~/cobot_ws/src
cp -a ~/Downloads/cobot2 ~/cobot_ws/src/cobot2

# 4) 애플리케이션 셋업 — 워크스페이스(DSR 드라이버 + RealSense + cobot2 colcon 빌드)
#    + 컨테이너(toolkit + 이미지 fetch + OPENAI_API_KEY 입력)
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
bash setup-app.sh                    # 기본: 컨테이너 이미지를 소스에서 빌드 (cobot2 템플릿을 수정해 개발하는 수업 흐름)
bash setup-app.sh --workspace-only   # 워크스페이스만 (DSR 드라이버 + RealSense + colcon)
bash setup-app.sh --containers-only  # 컨테이너만 (toolkit + 이미지 빌드 + OPENAI key)
bash setup-app.sh --reset            # doosan-robot2 재클론 + build/install/log 삭제 후 풀 빌드 (cobot2 보존)
bash setup-app.sh --fetch            # 컨테이너를 소스 빌드 대신 prebuilt 이미지로 fetch
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

> 아래 두 컨테이너의 `ROS_DOMAIN_ID=42` 는 setup-app 에서 고른 값(기본 42) — host·컨테이너가 동일해야 DDS discovery 성립.

**컨테이너 dev 이미지 빌드 (1회)** — `:dev-builder`(builder 스테이지)는 fetch 에 없으니 직접 빌드한다. cobot2 는 레포 외부라 빌드 컨텍스트로 staging 먼저:

```bash
DEV="-f $HOME/ros2_jazzy_test/containers/docker-compose.yml -f $HOME/ros2_jazzy_test/containers/docker-compose.dev.yml"
cd ~/ros2_jazzy_test
rm -rf cobot_ws/src/cobot2 && mkdir -p cobot_ws/src && cp -aT ~/cobot_ws/src/cobot2 cobot_ws/src/cobot2
docker compose $DEV build
```

**yolo 컨테이너**

소스 mount + 수동 기동 (`.py` 수정 → 노드 재실행이면 반영):

```bash
docker compose $DEV up -d yolo-detection      # 기동 시 clean colcon build 후 idle
docker exec -it yolo-detection bash
ros2 run object_detection object_detection    # Ctrl+C → host 에서 .py 수정 → 재실행
```

compose 없이 docker run 으로:

```bash
docker rm -f yolo-detection 2>/dev/null || true
docker run -d --name yolo-detection \
  --network host -w /ws --gpus all \
  -e ROS_DOMAIN_ID=42 -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
  -e CYCLONEDDS_URI=file:///cyclonedds.xml -e PYTHONUNBUFFERED=1 \
  -v ~/.config/cyclonedds/cyclonedds.xml:/cyclonedds.xml:ro \
  -v ~/cobot_ws/src/cobot2/yolo_container:/ws/src \
  -v yolo_build:/ws/build -v yolo_install:/ws/install \
  -v ~/ros2_jazzy_test/containers/dev/bashrc:/root/.bashrc:ro \
  local/ros2-jazzy-yolo:dev-builder \
  bash -c 'set +u; source /opt/ros/$ROS_DISTRO/setup.bash; find /ws/build /ws/install -mindepth 1 -delete 2>/dev/null || true; colcon build --symlink-install --merge-install; sleep infinity'
docker exec -it yolo-detection bash
ros2 run object_detection object_detection
```

**voice 컨테이너**

소스 mount + 수동 기동:

```bash
docker compose $DEV up -d voice-processing    # 기동 시 clean colcon build 후 idle
docker exec -it voice-processing bash
ros2 run voice_processing get_keyword         # Ctrl+C → host 에서 .py 수정 → 재실행
```

compose 없이 docker run 으로:

```bash
docker rm -f voice-processing 2>/dev/null || true
docker run -d --name voice-processing \
  --network host -w /ws \
  --env-file ~/ros2_jazzy_test/.env \
  -e ROS_DOMAIN_ID=42 -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
  -e CYCLONEDDS_URI=file:///cyclonedds.xml -e PYTHONUNBUFFERED=1 \
  -v ~/.config/cyclonedds/cyclonedds.xml:/cyclonedds.xml:ro \
  -v ~/ros2_jazzy_test/containers/voice-processing/asound.conf:/etc/asound.conf:ro \
  -v ~/cobot_ws/src/cobot2/voice_container:/ws/src \
  -v voice_build:/ws/build -v voice_install:/ws/install \
  -v ~/ros2_jazzy_test/containers/dev/bashrc:/root/.bashrc:ro \
  --device /dev/snd:/dev/snd --group-add audio \
  local/ros2-jazzy-voice:dev-builder \
  bash -c 'set +u; source /opt/ros/$ROS_DISTRO/setup.bash; find /ws/build /ws/install -mindepth 1 -delete 2>/dev/null || true; colcon build --symlink-install --merge-install; sleep infinity'
docker exec -it voice-processing bash
ros2 run voice_processing get_keyword
```

> 정지·삭제: `docker rm -f <name>` (dev 빌드 볼륨까지 비우려면 `docker volume rm yolo_build yolo_install voice_build voice_install`).

STT 트리거 — `get_keyword` 노드가 떠 있는 상태에서 host 의 다른 터미널에서 호출한다. 1회 호출이 (wakeword 대기 →) 5초 녹음 → Whisper STT → 키워드 추출까지 수행해 응답을 돌려준다(OPENAI_API_KEY·인터넷 필요):

```bash
source /opt/ros/jazzy/setup.bash
export ROS_DOMAIN_ID=42                                  # setup-app 에서 고른 값(기본 42). 컨테이너와 동일해야 함
ros2 service call /get_keyword std_srvs/srv/Trigger "{}"
# 응답 예: success=true, message='hammer / pos1' (도구 / 목적지)
```

**robot_control**

```bash
ros2 run robot_control robot_control   # real / virtual(에뮬레이터) 모두 동작 — RealSense 연결 필요 (virtual 은 실물 로봇 불필요)
```

### 컨테이너 없이 실행해 보기 (교육용 대비)

컨테이너 사용 효과를 비교하려면 모놀리식 노드를 host venv 로 직접 실행하는 실습 가이드를 따른다:
[`scripts/venv-demo/LAB.md`](scripts/venv-demo/LAB.md). 의존성 설치·네임스페이스·멀티터미널 기동을
한 줄씩 직접 수행하며, 컨테이너(`bringup.sh` + `docker compose`)가 대신 처리하던 작업량을 체감한다.
정식 설치 경로가 아니라 비교 학습용이다.
