# ROS2_Jazzy_Test

- Ubuntu 워크스테이션을 **ROS2 Jazzy 로봇 개발 환경**으로 일관되게 셋업하는 bash 설치 스크립트 모음
- 대상: Ubuntu 24.04 (noble) + NVIDIA GPU 워크스테이션

이 레포는 **base 환경 인스톨러**입니다. cobot2 애플리케이션 소스는 포함하지 않으므로, base 설치 후 cobot2 를 직접 배치하고 `setup-app.sh` 로 워크스페이스·컨테이너를 셋업합니다.

## 설치 순서

```bash
# 1) 저장소 클론 후 디렉토리 진입
git clone https://github.com/Seooooooogi/ros2_jazzy_test.git
cd ros2_jazzy_test

# 2) base 환경 설치 (kernel/NVIDIA/Docker/ROS2 + reboot + VS Code + DDS + 정적 IP + corecode, 10 step)
bash install.sh
```
- 시작 시 confirm 1회, 이후 자동 진행
- step 6 에서 1회 자동 reboot → 로그인 시 GUI autostart 로 자동 재개 (GUI 세션 필요, 복귀 후 sudo 비번 1회)
- autostart 등록 불가 환경이면 reboot 후 `bash install.sh` 재실행 (완료 단계는 자동 skip)
- OPENAI_API_KEY 는 install.sh 가 묻지 않음 — 아래 setup-app.sh(컨테이너 단계)에서 입력

```bash
# 3) cobot2 애플리케이션 소스 배치 — 이 레포는 cobot2 를 제공하지 않는다
mkdir -p ~/cobot_ws/src
cp -a <cobot2-source> ~/cobot_ws/src/cobot2

# 4) 애플리케이션 셋업 — 워크스페이스(DSR 드라이버 + RealSense + cobot2 colcon 빌드)
#    + 컨테이너(toolkit + 이미지 fetch + OPENAI_API_KEY 입력)
bash setup-app.sh
```
- 컨테이너 단계에서 OPENAI_API_KEY 입력 (빈 입력 = skip, 이후 `.env` 직접 편집 가능) — voice 컨테이너가 사용

## 옵션

base 설치 (`install.sh`):

```bash
bash install.sh --status    # 어느 단계까지 끝났는지 상태 출력
bash install.sh --reset     # 설치 상태 초기화 (처음부터 다시)
bash install.sh --verbose   # 각 step 상세 출력을 콘솔에도 표시
bash install.sh --help      # 도움말
```
- 단계별 상세 출력은 레포 루트 `install_log` 에 기록 (`--verbose` 면 콘솔에도)

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

환경 source (새 터미널마다):

```bash
source /opt/ros/jazzy/setup.bash
source ~/cobot_ws/install/setup.bash
set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a
```

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

**yolo 컨테이너**

기동(이미지 ENTRYPOINT 가 노드 자동 실행) + 로그:

```bash
docker compose -f ~/ros2_jazzy_test/containers/docker-compose.yml up -d yolo-detection
docker logs -f yolo-detection            # Ctrl+C 는 로그만 종료(컨테이너 유지)
```

> ℹ️ **dev 모드(아래 yolo·voice 공통)는 `:dev-builder` 이미지가 필요한데, `setup-app.sh` 의 fetch 엔 없다.** fetch(기본 셋업)는 프로덕션 `:dev` 만 받는다 — 노드 자동 실행 전용으로 소스가 이미지에 구워져 있어(`/ws/install` 만 포함, 빌드 도구 없음) **host 코드 수정이 반영되지 않는다**. 소스를 수정·디버깅하려면 `:dev-builder`(builder 스테이지)를 **로컬에서 1회 빌드**해야 한다. 한 번 만들면 이후엔 `.py` 수정 → 노드 재실행만으로 즉시 반영된다(`--symlink-install` — 매번 빌드가 아니다). compose 없이 `docker build` 로 풀어 쓰면:
>
> ```bash
> cd ~/ros2_jazzy_test                          # ★ 빌드 컨텍스트 = 레포 루트 (Dockerfile 폴더 아님)
>
> # 0) cobot2 소스를 빌드 컨텍스트로 staging — cobot2 는 외부화돼 레포에 없다(~/cobot_ws 에 있음).
> #    Dockerfile 이 COPY cobot_ws/src/cobot2/... 를 컨텍스트 기준으로 참조하므로 먼저 복사한다.
> #    (이 단계를 빠뜨리면 COPY 가 'not found → failed to compute cache key' 로 깨진다.
> #     build-all.sh 는 이 복사를 자동으로 한다.)
> rm -rf cobot_ws/src/cobot2 && mkdir -p cobot_ws/src
> cp -aT ~/cobot_ws/src/cobot2 cobot_ws/src/cobot2   # -T: cobot2 로 그대로 복사(중첩 방지). cobot_ws 는 gitignore.
>
> # yolo — builder 스테이지(--target). yolo 는 PyTorch CUDA wheel 결정용 CUDA_VERSION 추가.
> docker build -f containers/yolo-detection/Dockerfile --target builder \
>   --build-arg ROS_DISTRO=jazzy --build-arg CUDA_VERSION=12.8 \
>   -t local/ros2-jazzy-yolo:dev-builder .
> # voice — builder 스테이지.
> docker build -f containers/voice-processing/Dockerfile --target builder \
>   --build-arg ROS_DISTRO=jazzy \
>   -t local/ros2-jazzy-voice:dev-builder .
> ```
> 함정 3개: ① **cobot2 staging**(위 0단계) — cobot2 가 외부화돼 레포 컨텍스트에 없으므로 먼저 복사하지 않으면 `COPY cobot_ws/src/cobot2/...` 가 `not found → failed to compute cache key` 로 깨진다. ② 끝의 `.`(빌드 컨텍스트)는 **레포 루트** — `containers/<svc>/` 안에서 빌드하면 같은 식으로 깨진다. ③ `--target builder` 생략 시 마지막(runtime) 스테이지가 빌드돼 프로덕션 `:dev` 가 나온다 — dev 모드가 mount 할 idle 이미지가 안 됨. (compose 로 묶어 쓰려면 `docker compose -f containers/docker-compose.yml -f containers/docker-compose.dev.yml build <svc>` — 단 이 경우에도 0단계 staging 은 필요. 정식 빌드 경로는 staging+빌드를 자동화한 `containers/build-all.sh`.)

직접 들어가서 노드 실행 (dev override — 소스 수정 → 재실행 반복):

```bash
DEV="-f $HOME/ros2_jazzy_test/containers/docker-compose.yml -f $HOME/ros2_jazzy_test/containers/docker-compose.dev.yml"
docker compose $DEV up -d yolo-detection      # 기동 시 1회 colcon build 후 idle (노드 auto-run 끔)
docker exec -it yolo-detection bash           # /ws 진입, ROS overlay·venv PYTHONPATH 자동 source
ros2 run object_detection object_detection    # Ctrl+C 로 멈추고 host 에서 소스 수정 후 재실행 반복
```

compose 없이 (docker run 으로 풀어 쓰기) — compose 가 깔아주던 host network·GPU 패스스루(`--gpus all`)·cyclonedds mount 를 직접 명시한다. 위 compose 블록과 동작 동일(host 카메라 토픽이 먼저 떠 있어야 함):

```bash
# 프로덕션 (이미지 ENTRYPOINT 가 노드 자동 실행) — docker-compose.yml 의 yolo-detection 등가
docker rm -f yolo-detection 2>/dev/null || true   # 같은 이름의 기존 컨테이너(compose/직접 실행 잔재) 선제거 — 없으면 무시
docker run -d --name yolo-detection \
  --network host --restart unless-stopped --gpus all \
  -e ROS_DOMAIN_ID=42 -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
  -e CYCLONEDDS_URI=file:///cyclonedds.xml -e PYTHONUNBUFFERED=1 \
  -v ~/.config/cyclonedds/cyclonedds.xml:/cyclonedds.xml:ro \
  local/ros2-jazzy-yolo:dev
docker logs -f yolo-detection            # Ctrl+C 는 로그만 종료(컨테이너 유지)
```

> voice 와 차이: `--gpus all`(GPU 패스스루 — nvidia-container-toolkit 필요) · `/dev/snd`·`--env-file` 불요. 정지·삭제는 `docker rm -f yolo-detection`.

**voice 컨테이너**

기동(이미지 ENTRYPOINT 가 노드 자동 실행) + 로그:

```bash
docker compose -f ~/ros2_jazzy_test/containers/docker-compose.yml up -d voice-processing
docker logs -f voice-processing          # Ctrl+C 는 로그만 종료(컨테이너 유지)
```

직접 들어가서 노드 실행 (dev override) — `:dev-builder` 가 먼저 있어야 한다(fetch 엔 없음 → 위 yolo dev 의 ℹ️ 의 `docker build --target builder ... local/ros2-jazzy-voice:dev-builder .` 로 1회 빌드):

```bash
DEV="-f $HOME/ros2_jazzy_test/containers/docker-compose.yml -f $HOME/ros2_jazzy_test/containers/docker-compose.dev.yml"
docker compose $DEV up -d voice-processing    # 기동 시 1회 colcon build 후 idle (노드 auto-run 끔)
docker exec -it voice-processing bash         # /ws 진입, ROS overlay·venv PYTHONPATH 자동 source
ros2 run voice_processing get_keyword         # Ctrl+C 로 멈추고 host 에서 소스 수정 후 재실행 반복
```

compose 없이 (docker run 으로 풀어 쓰기) — compose 가 자동으로 깔아주던 host network·마이크 패스스루(`/dev/snd` + `audio` 그룹)·cyclonedds/asound mount 를 직접 명시한다. 위 compose 두 블록과 동작 동일:

```bash
# 프로덕션 (이미지 ENTRYPOINT 가 노드 자동 실행) — docker-compose.yml 의 voice-processing 등가
docker rm -f voice-processing 2>/dev/null || true   # 같은 이름의 기존 컨테이너(compose/직접 실행 잔재) 선제거 — 없으면 무시
docker run -d --name voice-processing \
  --network host --restart unless-stopped \
  --env-file ~/ros2_jazzy_test/.env \
  -e ROS_DOMAIN_ID=42 -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \
  -e CYCLONEDDS_URI=file:///cyclonedds.xml -e PYTHONUNBUFFERED=1 \
  -v ~/.config/cyclonedds/cyclonedds.xml:/cyclonedds.xml:ro \
  -v ~/ros2_jazzy_test/containers/voice-processing/asound.conf:/etc/asound.conf:ro \
  --device /dev/snd:/dev/snd --group-add audio \
  local/ros2-jazzy-voice:dev
docker logs -f voice-processing            # Ctrl+C 는 로그만 종료(컨테이너 유지)
```

```bash
# dev (소스 mount + 기동 시 1회 colcon build 후 idle, exec 로 수동 실행) — +docker-compose.dev.yml 등가
docker rm -f voice-processing 2>/dev/null || true   # 같은 이름의 기존 컨테이너(compose/직접 실행 잔재) 선제거 — 없으면 무시
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
docker exec -it voice-processing bash      # /ws 진입, ROS overlay·venv PYTHONPATH 자동 source
ros2 run voice_processing get_keyword      # Ctrl+C 로 멈추고 host 에서 소스 수정 후 재실행 반복
```

> 핵심 플래그: `--network host`(DDS discovery — host 노드와 토픽 공유) · `--device /dev/snd:/dev/snd` + `--group-add audio`(마이크 패스스루) · `asound.conf` mount(ALSA 기본 캡처를 hw:1,7 로 고정) · `--env-file`(OPENAI_API_KEY 주입). 정지·삭제는 `docker rm -f voice-processing` (dev 빌드 볼륨까지 초기화하려면 `docker volume rm voice_build voice_install`).
>
> ⚠ compose(`up -d voice-processing`)와 직접 `docker run` 은 **같은 고정 이름** `voice-processing` 을 쓴다. 한 방식으로 띄운 컨테이너가 (정지 상태로라도) 남아 있으면 다른 방식 기동이 `name is already in use` 로 실패한다 — 그래서 각 `docker run` 앞에 `docker rm -f` 를 둔다(compose 끼리 prod↔dev 전환도 동일).

STT 트리거(서비스 호출) — 컨테이너가 `get_keyword` 노드를 자동 실행하므로, 호출은 host 의 별도 터미널에서 한다. `ros2 service call` 1회가 (wakeword 대기 →) 5초 녹음 → Whisper STT → 키워드 추출까지 1회 수행하고 결과를 응답으로 돌려준다:

```bash
source /opt/ros/jazzy/setup.bash
export ROS_DOMAIN_ID=42                                  # 컨테이너와 같은 도메인(필수)
ros2 service call /get_keyword std_srvs/srv/Trigger "{}"
# 응답 예: success=true, message='hammer / pos1' (도구 / 목적지)
```

> STT(Whisper)·키워드 추출은 voice 컨테이너에 OPENAI_API_KEY 가 주입돼 있어야(`.env`) 동작하고, 인터넷(api.openai.com) 연결이 필요하다. 진행 로그는 `docker logs -f voice-processing` 로 확인.

**robot_control**

```bash
ros2 run robot_control robot_control   # real / virtual(에뮬레이터) 모두 동작 — RealSense 연결 필요 (virtual 은 실물 로봇 불필요)
```

### 2) 통합 기동

```bash
# 로봇 드라이버 + 카메라 + 컨테이너 (Ctrl+C 로 일괄 정리). 실기=mode:=real / 에뮬레이터=mode:=virtual
bash ~/ros2_jazzy_test/containers/bringup.sh mode:=real
ros2 run robot_control robot_control   # real / virtual(에뮬레이터) 모두 동작 — RealSense 연결 필요 (virtual 은 실물 로봇 불필요)
```

### 컨테이너 없이 실행해 보기 (교육용 대비)

컨테이너 사용 효과를 비교하려면 모놀리식 노드를 host venv 로 직접 실행하는 실습 가이드를 따른다:
[`scripts/venv-demo/LAB.md`](scripts/venv-demo/LAB.md). 의존성 설치·네임스페이스·멀티터미널 기동을
한 줄씩 직접 수행하며, 컨테이너(`bringup.sh` + `docker compose`)가 대신 처리하던 작업량을 체감한다.
정식 설치 경로가 아니라 비교 학습용이다.
