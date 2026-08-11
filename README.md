# Cobot2 Jazzy Installer

- Ubuntu 워크스테이션을 **ROS2 Jazzy 로봇 개발 환경**으로 일관되게 셋업하는 bash 설치 스크립트 모음
- 대상: Ubuntu 24.04 (noble) + NVIDIA GPU 워크스테이션

## 설치 순서

```bash
# 1) 저장소 클론 후 디렉토리 진입
git clone https://github.com/ROKEY-SPARK/cobot2_jazzy_installer.git
cd cobot2_jazzy_installer

# 2) base 환경 설치 (kernel/NVIDIA/Docker/ROS2 + reboot + VS Code + DDS + 정적 IP, 9 step)
bash install.sh
```

```bash
# 3) cobot2 애플리케이션 소스 배치
mkdir -p ~/cobot2_ws/src ~/cobot_venv_ws/src
cp -a ~/Downloads/cobot2 ~/cobot2_ws/src/cobot2

# 3-1) pick & place 실습 패키지는 별도 워크스페이스로 분리
#      (~/cobot_venv_ws 는 venv 실습 전용 — 아래 setup-app.sh 가 건드리지 않는다.
#       venv 생성·pip 설치·colcon 빌드 절차는 별도 실습 안내를 따른다.)
mv ~/cobot2_ws/src/cobot2/pick_and_place_{text,voice} ~/cobot_venv_ws/src/
rm -f ~/cobot_venv_ws/src/pick_and_place_*/COLCON_IGNORE

# 3-2) voice OPENAI 키 배치 — 키를 명령줄에 직접 치면 ~/.bash_history 에 평문으로 남는다.
#      아래는 입력이 stdin 이라 history 에도, 화면에도 남지 않는다.
read -rsp 'OPENAI API key: ' K \
  && printf 'OPENAI_API_KEY=%s\n' "$K" > ~/cobot2_ws/src/cobot2/voice_processing/resource/.env \
  && unset K && echo

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
bash install.sh --no-nvidia-driver  # NVIDIA 드라이버 설치 단계 건너뜀 (드라이버를 이미 별도 설치한 머신용)
bash install.sh --help      # 도움말
```

애플리케이션 (`setup-app.sh`):

```bash
bash setup-app.sh                    # 기본: :dev-builder 컨테이너 이미지를 소스에서 빌드
bash setup-app.sh --workspace-only   # 워크스페이스만
bash setup-app.sh --containers-only  # 컨테이너만
bash setup-app.sh --reset            # doosan-robot2 · onrobot-ros2 · m0609 링크 + build/install/log 삭제 후 풀 빌드
                                     #   (cobot2 소스와 ~/m0609_rg2_integration 원본은 보존)
bash setup-app.sh --help
```

---

## 실행

환경 source. 매 터미널마다 아래를 실행:

```bash
source /opt/ros/jazzy/setup.bash
source ~/cobot2_ws/install/setup.bash
set -a; source ~/cobot2_jazzy_installer/resources/config.sh; set +a
```

> 💡 **매번 치기 싫으면 `~/.bashrc` 에 1회 등록**
> ```bash
> # >>> cobot2_jazzy_installer env >>>
> [ -f ~/cobot2_ws/install/setup.bash ] && source ~/cobot2_ws/install/setup.bash
> set -a; source ~/cobot2_jazzy_installer/resources/config.sh; set +a
> # <<< cobot2_jazzy_installer env <<<
> ```
>
> 마커 이름은 설치 스크립트가 쓰는 것과 같아야 한다 — 다르면 `hostcfg.sh` 가 자기 블록을
> 못 찾아 같은 줄이 두 벌 쌓인다. 레포 이름이 바뀌기 전에 깔린 `ros2_jazzy_test` 마커
> 블록은 설치 스크립트가 다음 실행에서 알아서 지운다.

### 기동

**로봇 드라이버 + 그리퍼** (`m0609_rg2_bringup`)

```bash
# 에뮬레이터 (기본값)
ros2 launch m0609_rg2_bringup bringup.launch.py mode:=virtual
# 실기
ros2 launch m0609_rg2_bringup bringup.launch.py mode:=real host:=192.168.1.100
```

- 인자: `mode`(virtual|real) / `host` / `port` / `rt_host` / `camera` / `rviz`
- `camera` 기본값은 **false** — 카메라는 아래 블록으로 따로 띄우거나 `camera:=true` 로 함께 띄운다
- 그리퍼·브라켓 없이 로봇 드라이버만 필요하면 `ros2 launch dsr_bringup2 dsr_bringup2_rviz.launch.py mode:=real host:=192.168.1.100 port:=12345 model:=m0609 name:=dsr01`

**RealSense 카메라** (따로 띄울 때)

```bash
ros2 run realsense2_camera realsense2_camera_node --ros-args \
  -r __ns:=/ -r __node:=camera \
  -p enable_color:=true -p enable_depth:=true \
  -p depth_module.depth_profile:=848x480x30 -p rgb_camera.color_profile:=1280x720x30 \
  -p align_depth.enable:=true -p enable_rgbd:=true -p enable_sync:=true \
  -p pointcloud.enable:=true -p pointcloud.stream_filter:=2 -p initial_reset:=true
```

- `-r __ns:=/ -r __node:=camera` 두 remap 이 **필수**다. 안 주면 드라이버 기본 네임스페이스(`/camera`)와
  노드 이름(`camera`)이 겹쳐 토픽이 `/camera/camera/*` 로 나온다.
- 소비자(`object_detection`, `pick_and_place_*` 의 `ImgNode`)는 `/camera/color/image_raw` 등을
  **절대 경로**로 구독하므로, 경로가 어긋나면 에러 없이 토픽만 빈 채로 대기한다.
- 타 자료의 `ros2 launch realsense2_camera rs_align_depth_launch.py ...` 는 `/camera/camera/*` 를 낸다 — 위 명령으로 대체.

**통합 실행 (권장)**

```bash
bash containers/bringup.sh                 # virtual(emulator) + camera + yolo 컨테이너 + host voice (노드까지 자동 기동)
bash containers/bringup.sh mode:=real      # real robot
```

**yolo 컨테이너**

컨테이너 생성 — **최초 1회**


```bash
docker run -d --name yolo-detection \
  --network host -w /ws --gpus all --shm-size=8g \
  -e ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-0} -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
  -e CYCLONEDDS_URI=file:///cyclonedds.xml -e PYTHONUNBUFFERED=1 \
  -v ~/.config/cyclonedds/cyclonedds.xml:/cyclonedds.xml:ro \
  -v ~/cobot2_ws/src/cobot2/yolo_container:/ws/src \
  -v yolo_build:/ws/build -v yolo_install:/ws/install \
  -v ~/yolo_train:/train \
  -v ~/cobot2_jazzy_installer/containers/dev/bashrc:/root/.bashrc:ro \
  docker.io/local/ros2-jazzy-yolo:dev-builder \
  bash -c 'set +u; source /opt/ros/$ROS_DISTRO/setup.bash; find /ws/build /ws/install -mindepth 1 -delete 2>/dev/null || true; colcon build --symlink-install --merge-install; sleep infinity'
```

- `--shm-size=8g` / `-v ~/yolo_train:/train` 은 컨테이너 안에서 YOLO 학습을 돌릴 때 필요하다
  (DataLoader 공유메모리 · 데이터셋과 `runs/` 산출물을 host 에 보존).
- 인자를 바꾸려면 `docker rm -f yolo-detection` 후 재생성 1회. 평소에는 `start` / `stop` 만 쓴다.

컨테이너 시작

```bash
docker start yolo-detection
docker stop yolo-detection
```

컨테이너 진입
```bash
docker exec -it yolo-detection bash
```

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
