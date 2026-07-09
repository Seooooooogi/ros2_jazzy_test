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
#    + 컨테이너(toolkit + :dev-builder 이미지 빌드 + OPENAI_API_KEY 입력)
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
bash setup-app.sh --workspace-only   # 워크스페이스만 (DSR 드라이버 + RealSense + colcon)
bash setup-app.sh --containers-only  # 컨테이너만 (toolkit + 이미지 빌드 + OPENAI key)
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

**RealSense 카메라**

```bash
ros2 launch realsense2_camera rs_align_depth_launch.py \
  depth_module.depth_profile:=848x480x30 rgb_camera.color_profile:=1280x720x30 \
  align_depth.enable:=true enable_rgbd:=true pointcloud.enable:=true initial_reset:=true
```

**통합 실행**

```bash
bash containers/bringup.sh                 # virtual(emulator) + camera + containers (노드까지 자동 기동)
bash containers/bringup.sh mode:=real      # real robot
```

**컨테이너 개별 수동 실행**

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

**플래그 해설**

- `docker rm -f yolo-detection 2>/dev/null || true` : 같은 이름 컨테이너가 있으면 강제 삭제
- `-d` : detached — 백그라운드 실행
- `--name yolo-detection` : 컨테이너 이름 고정
- `--network host` : host 네트워크를 그대로 공유
- `-w /ws` : 컨테이너 안 작업 디렉토리를 `/ws` 로 설정
- `--gpus all` : host GPU 전부를 컨테이너에 전달
- `-e ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-0}` : ROS DOMAIN ID 값이 있으면 그 값, 없으면 `0`
- `-e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp` : DDS 구현을 CycloneDDS 로 고정
- `-e CYCLONEDDS_URI=file:///cyclonedds.xml` : CycloneDDS 설정 파일 경로
- `-e PYTHONUNBUFFERED=1` : 파이썬 출력 버퍼링을 꺼 로그가 즉시 보이게
- `-v host경로:컨테이너경로:ro` : host 파일/폴더를 컨테이너 안에 연결
  - `…/cyclonedds.xml:/cyclonedds.xml:ro` : DDS 설정 주입
  - `…/yolo_container:/ws/src` : host 소스 mount → `.py` 를 고치면 컨테이너가 곧바로 봄
  - `yolo_build:/ws/build`, `yolo_install:/ws/install` : named volume(도커가 관리하는 저장소)에 빌드 산출물 보관
  - `…/dev/bashrc:/root/.bashrc:ro` : 컨테이너 셸 진입 시 ROS 환경을 자동 source
- `local/ros2-jazzy-yolo:dev-builder` : 실행할 이미지(태그 `dev-builder` 고정)
- `bash -c '…'` : 컨테이너가 뜨면서 실행할 명령. 내부 순서:
  - `source /opt/ros/$ROS_DISTRO/setup.bash` : ROS 환경 로드
  - `find /ws/build /ws/install -mindepth 1 -delete 2>/dev/null || true` : 이전 빌드 산출물 삭제(clean build)
  - `colcon build --symlink-install --merge-install` : 워크스페이스 빌드(`--symlink-install`=산출물 심링크)
  - `sleep infinity` : 컨테이너 진입 가능 상태 유지

빌드 완료까지 대기 → 진입:

```bash
docker logs -f yolo-detection                 # "Summary: N package finished" 뜨면 Ctrl+C
docker exec -it yolo-detection bash
```

컨테이너 안에서 노드 실행:

```bash
ros2 run object_detection object_detection    # Ctrl+C → host 에서 .py 수정 → 재실행
```

**voice 컨테이너**

기동 (compose):

```bash
DEV="-f $HOME/ros2_jazzy_test/containers/docker-compose.yml -f $HOME/ros2_jazzy_test/containers/docker-compose.dev.yml"
docker compose $DEV up -d voice-processing    # 기동 시 clean colcon build 후 idle
```

또는 compose 없이 docker run:

```bash
docker rm -f voice-processing 2>/dev/null || true
docker run -d --name voice-processing \
  --network host -w /ws \
  --env-file ~/ros2_jazzy_test/.env \
  -e ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-0} -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
  -e CYCLONEDDS_URI=file:///cyclonedds.xml -e PYTHONUNBUFFERED=1 \
  -v ~/.config/cyclonedds/cyclonedds.xml:/cyclonedds.xml:ro \
  -v ~/ros2_jazzy_test/containers/voice-processing/asound.conf:/etc/asound.conf:ro \
  -v ~/cobot_ws/src/cobot2/voice_container:/ws/src \
  -v voice_build:/ws/build -v voice_install:/ws/install \
  -v ~/ros2_jazzy_test/containers/dev/bashrc:/root/.bashrc:ro \
  --device /dev/snd:/dev/snd --group-add audio \
  local/ros2-jazzy-voice:dev-builder \
  bash -c 'set +u; source /opt/ros/$ROS_DISTRO/setup.bash; find /ws/build /ws/install -mindepth 1 -delete 2>/dev/null || true; colcon build --symlink-install --merge-install; sleep infinity'
```

**플래그 해설** (yolo `docker run` 과 동일, 차이점만 기술)

- `--env-file ~/ros2_jazzy_test/.env` : `.env` 의 변수들(특히 `OPENAI_API_KEY`)을 컨테이너 환경으로 주입
- `-v …/asound.conf:/etc/asound.conf:ro` : ALSA 사운드 설정 주입(마이크 장치 매핑)
- `--device /dev/snd:/dev/snd` : host 사운드 장치를 컨테이너에 노출(마이크 입력)
- `--group-add audio` : 컨테이너 프로세스를 `audio` 그룹에 추가 → `/dev/snd` 접근 권한
- `--gpus all` **없음** : voice 는 GPU 불필요

빌드 완료까지 대기 → 진입:

```bash
docker logs -f voice-processing               # "Summary: N package finished" 뜨면 Ctrl+C
docker exec -it voice-processing bash
```

컨테이너 안에서 노드 실행:

```bash
ros2 run voice_processing get_keyword         # Ctrl+C → host 에서 .py 수정 → 재실행
```

STT 트리거 — `get_keyword` 노드가 떠 있는 상태에서 host 의 다른 터미널에서 호출한다. 1회 호출이 (wakeword 대기 →) 5초 녹음 → Whisper STT → 키워드 추출까지 수행해 응답을 돌려준다(OPENAI_API_KEY·인터넷 필요):

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
