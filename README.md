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

> 아래 두 컨테이너의 `ROS_DOMAIN_ID=42` 는 설치 시 고른 값(기본 42) — host·컨테이너가 동일해야 DDS discovery 성립.

**yolo 컨테이너**

```bash
docker rm -f yolo-detection 2>/dev/null || true
docker run -d --name yolo-detection \
  --network host --restart unless-stopped --gpus all \
  -e ROS_DOMAIN_ID=42 -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
  -e CYCLONEDDS_URI=file:///cyclonedds.xml -e PYTHONUNBUFFERED=1 \
  -v ~/.config/cyclonedds/cyclonedds.xml:/cyclonedds.xml:ro \
  local/ros2-jazzy-yolo:dev
docker logs -f yolo-detection            # Ctrl+C 는 로그만 종료(컨테이너 유지)
```


**voice 컨테이너**

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
  bash -c 'set +u; source /opt/ros/$ROS_DISTRO/setup.bash; colcon build --symlink-install --merge-install || true; sleep infinity'
docker exec -it voice-processing bash
ros2 run voice_processing get_keyword      # docker 진입 후 실행
```

```bash
source /opt/ros/jazzy/setup.bash
export ROS_DOMAIN_ID=42                                  # 설치 시 고른 값(기본 42). 컨테이너와 동일해야 함
ros2 service call /get_keyword std_srvs/srv/Trigger "{}"
# 응답 예: success=true, message='hammer / pos1' (도구 / 목적지)
```

**robot_control**

```bash
ros2 run robot_control robot_control   # real / virtual(에뮬레이터) 모두 동작 — RealSense 연결 필요 (virtual 은 실물 로봇 불필요)
```

### 2) 통합 기동

```bash
# 로봇 드라이버 + 카메라 + 컨테이너 (Ctrl+C 로 일괄 정리).
bash ~/ros2_jazzy_test/containers/bringup.sh mode:=real
ros2 run robot_control robot_control
```
