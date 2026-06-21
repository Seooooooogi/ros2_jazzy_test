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

전체 `install.sh` 없이 colcon 워크스페이스 `~/cobot_ws` 만 다시 빌드한다. 소스만 고쳤거나 워크스페이스가 깨졌을 때 쓴다.

```bash
bash reinstall-workspace.sh           # 증분: 레포 소스 재동기화 + colcon 증분 빌드
bash reinstall-workspace.sh --clean   # 전체: doosan-robot2 재클론 + build/install/log 삭제 후 풀 빌드
bash reinstall-workspace.sh --help
```

- 기본(증분): 레포의 `cobot1`/`cobot2` 그룹 소스를 `~/cobot_ws/src` 로 다시 미러(항상 fresh) 후 colcon 증분 빌드. 기존 `doosan-robot2` clone·빌드 산출물은 유지 → 빠름.
- `--clean`: `doosan-robot2` 재클론 + `build`/`install`/`log` 삭제 후 처음부터 빌드(삭제 전 확인 프롬프트, `--yes` 로 스킵).
- DSR 의존성·에뮬레이터 이미지도 멱등 재확인(이미 있으면 빠르게 skip) → `sudo` 가 필요할 수 있다(`install.sh` 와 동일).

## 환경 source (host — 새 터미널마다)

host 에서 ROS 명령(`ros2 launch`, `ros2 run`)을 쓰기 전에 매 터미널에서 1회.

```bash
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash   # overlay (dsr_bringup2 / robot_control 제공)
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a   # RMW(CycloneDDS) / domain
```

## 컨테이너 노드 개별 실행 (개발 모드)

dev 모드로 띄운 컨테이너는 노드를 자동 실행하지 않는다. 셸에 들어가 워크스페이스(`/ws` — host `~/cobot_ws` 소스가 bind-mount)에서 노드를 **직접** 실행한다. 코드 수정이 즉시 반영돼 디버깅에 쓴다.

- 전제: `~/cobot_ws` 가 빌드돼 있어야 한다(`install.sh` 또는 위 `reinstall-workspace.sh`). dev 모드는 그 안의 `cobot2/yolo_container`·`cobot2/voice_container` 를 `/ws/src` 로 mount 한다.

```bash
# 프로덕션 정의 + dev override 를 함께 머지 (cwd 무관 — 절대경로)
DEV="-f $HOME/ros2_jazzy_test/containers/docker-compose.yml -f $HOME/ros2_jazzy_test/containers/docker-compose.dev.yml"
docker compose $DEV build            # 최초 1회 — dev-builder 이미지 (프로덕션 이미지와 분리)
```

**yolo** — `object_detection` 노드, `/get_3d_position` 서비스 server

```bash
docker compose $DEV up -d yolo-detection
docker exec -it yolo-detection bash          # /ws 로 진입, ROS overlay·venv 자동 source
ros2 run object_detection object_detection   # 수정 → Ctrl+C → 재실행 반복
```

**voice** — `voice_processing` 노드(`get_keyword`), `/get_keyword` 서비스 server

```bash
docker compose $DEV up -d voice-processing
docker exec -it voice-processing bash
ros2 run voice_processing get_keyword
```

- `.py` 수정은 노드 재시작만으로 반영(`--symlink-install`). `od_msg` 의 `.srv`(메시지) 수정은 컨테이너 안에서 `colcon build` 재실행 필요.
- 자세한 dev 모드 설명은 `containers/README.md` 참조.

## robot_control 전체 실행 순서

`robot_control` 은 host 노드로, voice 의 `/get_keyword` 와 yolo 의 `/get_3d_position` 을 client 로 호출하며 DSR 로봇을 제어한다. 따라서 두 서비스 + 카메라 + 드라이버가 먼저 떠 있어야 한다. 각 단계는 **별도 터미널**에서 띄우고, host 노드는 위 "환경 source" 를 먼저 한다.

전제: `install.sh` 완료(`~/cobot_ws` 빌드 + `cyclonedds.xml` 렌더) + `.env` 의 `OPENAI_API_KEY`(voice).

1. **DSR 드라이버** — 실기 `mode:=real`, 에뮬레이터 `mode:=virtual`

   ```bash
   ros2 launch dsr_bringup2 dsr_bringup2_rviz.launch.py \
     mode:=real host:=192.168.1.100 port:=12345 model:=m0609 name:=dsr01
   ```

2. **RealSense 카메라** (host 소유 — `align_depth.enable:=true` 필수, 미설정 시 yolo depth 계산 실패)

   ```bash
   ros2 launch realsense2_camera rs_align_depth_launch.py \
     depth_module.depth_profile:=848x480x30 rgb_camera.color_profile:=1280x720x30 \
     align_depth.enable:=true enable_rgbd:=true pointcloud.enable:=true initial_reset:=true
   ```

3. **yolo 노드** — 위 "컨테이너 노드 개별 실행"의 yolo 단계 (`docker compose $DEV up -d yolo-detection` → exec → `ros2 run object_detection object_detection`)

4. **voice 노드** — 위의 voice 단계 (`docker compose $DEV up -d voice-processing` → exec → `ros2 run voice_processing get_keyword`)

5. **robot_control** (host — 오케스트레이터, 위 두 서비스 + DSR 의 client)

   ```bash
   ros2 run robot_control robot_control
   ```

> **한 줄 대안 (프로덕션 자동 기동)**: 1~4 단계를 통합 launch 한 줄로 묶는다. 빌드/pull 된 **프로덕션** 이미지를 쓰며 컨테이너 노드는 기동과 동시에 auto-run(`object_detection`/`get_keyword`)된다. 이후 robot_control 만 별도 실행.
>
> ```bash
> ros2 launch cobot2_bringup bringup_all.launch.py mode:=real   # DSR + 카메라 + yolo/voice 컨테이너
> ros2 run robot_control robot_control                          # 인프라 기동 후 별도 터미널
> ```
>
> 프로덕션 컨테이너만 따로 띄우려면: `docker compose -f ~/ros2_jazzy_test/containers/docker-compose.yml up -d` (노드 auto-run · 종료는 `... down`).

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
