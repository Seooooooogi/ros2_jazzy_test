# ros2_jazzy_test

- Ubuntu 워크스테이션을 **ROS2 Jazzy 로봇 개발 환경**으로 일관되게 셋업하는 bash 설치 스크립트 모음
- 구성: NVIDIA 드라이버 + Docker + ROS2 Jazzy + Doosan DSR + RealSense + 음성(LangChain)
- 대상: Ubuntu 24.04 (noble) + NVIDIA GPU 워크스테이션
- 전제: 동일 모델 머신에 반복 설치/검증

## 설치 순서

- 권장 진입점: `install.sh` 하나
- 내부 실행 순서: `a01 → reboot → a02 → a03 → a04` (단일 시퀀스, `[n/total]` 진행률)
- 완료된 단계는 자동 skip

```bash
# 1) 저장소 클론 후 디렉토리 진입
git clone https://github.com/Seooooooogi/ros2_jazzy_test.git ros2_jazzy_test
cd ros2_jazzy_test

# 2) 전체 설치 시작 — 무인 설치(기본). 시작 시 OPENAI_API_KEY + 진행 동의만 받고
#    reboot·재개를 자동 처리. reboot 후 GUI 로그인 시 터미널이 자동으로 떠 이어진다
#    (복귀 후 sudo 비번 1회). GUI 세션 필요.
bash install.sh --unattended
```

- **재개 가능(resumable)** — 실패/리부트로 끊겨도 마지막 성공 단계 기록
- 재실행 시 처음이 아니라 다음 단계부터 진행
- (대안) 수동 진행 — `--unattended` 없이 `bash install.sh`. reboot 발생 시 부팅 후 같은 명령(`bash install.sh`)을 다시 실행해 다음 단계부터 이어서 진행

## 자주 쓰는 옵션

```bash
bash install.sh --unattended  # 무인 설치 (reboot 자동·복귀 시 자동 재개; GUI 세션 필요) — 기본
bash install.sh            # 수동 진행 (reboot 후 같은 명령 재실행)
bash install.sh --status   # 어느 단계까지 끝났는지 상태 출력
bash install.sh --reset    # 설치 상태 초기화 (처음부터 다시)
bash install.sh --help     # 도움말
```

- 콘솔 출력: `[n/total]` 진행률 + 경고/에러만
- 단계별 상세 출력(apt/pip/colcon): `~/.ros2_jazzy_test/install.log` 에 append
- 상세 출력 실시간 확인: `VERBOSE=1 bash install.sh`

## 환경 변수 / 시크릿

- 음성 처리용 API 키 등은 `.env` 로 관리
- 템플릿: `.env.example` (복사 후 값 입력)
- `.env` 는 절대 커밋 금지

```bash
cp .env.example .env
# .env 편집해 실제 키 입력
```

## 워크스페이스 (cobot2_ws) 빌드 / 위치

- a02 단계(로봇/카메라): 워크스페이스 **자동 clone + 빌드** — 별도 수동 빌드 불필요
- 기본 위치: `~/cobot2_ws` (환경변수 `DSR_WORKSPACE` 로 변경 가능)
- 구성: `doosan-robot2`(jazzy) clone + host 패키지(`robot_control`, `od_msg`)만 복사 후 `colcon build`
  - app 패키지(`object_detection` / `voice_processing` 등)는 host ws 에 없음 — yolo/voice 컨테이너가 담당
- doosan-robot2(jazzy) 소스 호환 패치(서비스 이름·prefix) a02 에서 자동 적용 → **손수 clone 시 패치 누락으로 런타임 깨짐**

수정 후 재빌드:

```bash
cd ~/cobot2_ws
source /opt/ros/jazzy/setup.bash
colcon build
source install/setup.bash
```

다른 위치(예: 바탕화면)에 두고 빌드 — `DSR_WORKSPACE` 지정 후 설치 실행 (패치 포함 전체 파이프라인이 그 경로에서 수행):

```bash
DSR_WORKSPACE=~/Desktop/cobot2_ws bash install.sh
# 이후 재빌드도 같은 경로에서: cd ~/Desktop/cobot2_ws && colcon build
```

## 설치 후 실행 — 통합 bringup (로봇 + 카메라 + 컨테이너 한 번에)

환경 source (새 터미널마다):

```bash
source /opt/ros/jazzy/setup.bash
source ~/cobot2_ws/install/setup.bash   # overlay (dsr_bringup2 / robot_control 제공)
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a   # RMW(CycloneDDS) / domain
```

드라이버 + RealSense + yolo/voice 컨테이너를 한 줄로 기동 (`cobot2_bringup` 패키지 — colcon overlay source 후 패키지명으로 호출):

```bash
ros2 launch cobot2_bringup bringup_all.launch.py mode:=real
```

- 실기 IP는 `192.168.1.100` 고정 (launch 기본값) — 다른 컨트롤러면 `host:=<ip>`
- `mode:=virtual` — 에뮬레이터 (컨트롤러 연결 없이)
- `camera:=false` — RealSense 제외 / `containers:=false` — 컨테이너 제외
- Ctrl+C 시 컨테이너 자동 정리 (`docker compose down`)

컨테이너만 따로 띄우려면:

```bash
docker compose -f ~/ros2_jazzy_test/containers/docker-compose.yml up -d
```

- **각 컨테이너는 기동과 동시에 노드를 자동 실행** — yolo=`object_detection`, voice=`get_keyword`. 별도 `ros2 run` 불필요
- 노드 로그 확인: `docker compose -f ~/ros2_jazzy_test/containers/docker-compose.yml logs -f`

컨테이너 포함 시 전제:

- 이미지 확보 — `install.sh` step14 가 공개 드라이브에서 받아 `docker load`(자동). 수동은 `bash containers/fetch-images.sh`, 직접 빌드는 `bash containers/build-all.sh`
- `.env` 존재 (voice 의 `OPENAI_API_KEY` 런타임 주입)
- `~/.ros2_jazzy_test/cyclonedds.xml` 렌더 완료 (dds-tuning — install.sh 마지막 단계)
- 카메라는 host 소유 → yolo 컨테이너가 host RealSense 토픽을 DDS 로 구독 (컨테이너 안에 카메라 없음)

### 시각화 (선택) — 실시간 카메라 + YOLO + 음성 상태

RealSense 화면에 YOLO 실시간 박스·클래스 + 좌상단 wakeword/target/pos 를 겹쳐 띄우는 관찰용 창. 카메라가 떠 있어야 한다 (위 bringup 또는 맨 아래 개별 실행).

```bash
# 1) 추론 컨테이너 — viz 프로파일 (평소 up 엔 미포함). 박스만 /yolo/detections 로 publish
docker compose -f ~/ros2_jazzy_test/containers/docker-compose.yml --profile viz up -d yolo-viz

# 2) host 뷰어 창 (새 터미널 — 환경 source 후, q 로 종료)
source /opt/ros/jazzy/setup.bash
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
python3 ~/ros2_jazzy_test/viz/viewer.py
```

- 컨테이너가 박스만 보내고 host 뷰어가 원본 프레임 위에 합성 (host 는 apt cv2/cv_bridge 만 사용 — pip 불필요)
- 좌상단 target/pos 는 robot_control 이 돌 때만 채워진다 (아니면 `-`)
- 토픽 / 트러블슈팅 상세: `viz/README.md`

**robot_control(실제 pick 모션)은 분리 실행** — bringup/컨테이너로 인프라를 올린 뒤 별도 터미널에서:

```bash
ros2 run robot_control robot_control
```

- 음성 명령 흐름이라 Ctrl+C 로 자주 재기동 → 전용 터미널 권장
- bringup launch 는 인프라만 올리고 자율 모션을 일으키지 않음 — 작업 시작은 이 명령으로 분리

## 설치 후 실행 — 로봇 · 카메라 (개별 실행)

환경 source (새 터미널마다):

```bash
source /opt/ros/jazzy/setup.bash
source ~/cobot2_ws/install/setup.bash   # overlay (dsr_bringup2 / robot_control 제공)
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a   # RMW(CycloneDDS) / domain
```

로봇 드라이버 (실로봇 — 컨트롤러 IP 지정):

```bash
ros2 launch dsr_bringup2 dsr_bringup2_rviz.launch.py \
  mode:=real host:=192.168.1.100 port:=12345 model:=m0609 name:=dsr01
```

- 에뮬레이터로 띄우려면 `mode:=virtual` (컨트롤러 연결 없이)

RealSense 카메라 (검증된 프로파일):

```bash
ros2 launch realsense2_camera rs_align_depth_launch.py \
  depth_module.depth_profile:=848x480x30 rgb_camera.color_profile:=1280x720x30 \
  align_depth.enable:=true enable_rgbd:=true pointcloud.enable:=true initial_reset:=true
```

- `align_depth.enable:=true` 필수 — 없으면 `aligned_depth_to_color` 미publish
