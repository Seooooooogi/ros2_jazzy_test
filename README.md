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
mkdir -p ~/cobot_ws/src
cp -a ~/Downloads/cobot2 ~/cobot_ws/src/cobot2

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

**통합 실행 (권장)** — yolo `:dev-builder` 이미지는 `setup-app.sh` 가 이미 빌드했고, voice 는 host 에 직접 설치돼 있다. 로봇 + 카메라 + yolo 컨테이너 + host voice 노드를 한 번에 올리고 Ctrl+C 로 확실히 내리려면:

```bash
bash containers/bringup.sh                 # virtual(emulator) + camera + yolo 컨테이너 + host voice (노드까지 자동 기동)
bash containers/bringup.sh mode:=real      # real robot
```

**기동 인자**

- `mode:=real` : 실물 로봇 기동(생략 시 기본 `virtual` 에뮬레이터).

> bringup 은 컨테이너 안 colcon build 가 끝나길 기다렸다가 각 노드를 자동 기동한다. 개별 컨테이너를 직접 다뤄 보려면 아래 수동 절차를 따른다(디버깅/학습용). 이미지 수동 재빌드는 `bash containers/build-all.sh`(cobot2 staging + 빌드 + 검증).

**컨테이너 개별 수동 실행** — 각 compose 블록 첫 줄의 `DEV` 로 base + dev override 두 compose 파일을 머지한다.

**compose 인자**

- `DEV="-f a -f b"` : compose 파일 2개를 위→아래 순으로 머지(base + dev override). 각 블록에 인라인해 복붙 시 자기완결.
- `docker compose $DEV up -d <service>` : 지정 서비스만 백그라운드(`-d`)로 기동.

> **블록을 위에서부터 하나씩** 실행한다(한 번에 붙여넣지 않는다). 특히 기동 직후엔 컨테이너 안 colcon build 가 끝날 때까지 `docker logs -f` 로 기다린 뒤 `docker exec` 한다 — 빌드 중 진입하면 overlay 가 덜 써진 상태라 `not found: "/ws/install/local_setup.bash"` 경고가 뜬다(무해하지만 노드는 패키지를 못 찾는다).

**yolo 컨테이너** — 소스 mount + 수동 기동 (`.py` 수정 → 노드 재실행이면 반영).

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

- `docker rm -f yolo-detection 2>/dev/null || true` : 같은 이름 컨테이너가 있으면 강제 삭제. 없어서 나는 에러는 `2>/dev/null`(에러 메시지 버림)+`|| true`(실패해도 다음 줄 진행)로 넘겨 재실행해도 안전.
- `-d` : detached — 백그라운드 실행(터미널을 잡지 않음).
- `--name yolo-detection` : 컨테이너 이름 고정(뒤의 `logs`/`exec`/`rm` 이 이 이름으로 지목).
- `--network host` : host 네트워크를 그대로 공유 → DDS 디스커버리(노드 자동 발견)가 컨테이너 경계를 넘음.
- `-w /ws` : 컨테이너 안 작업 디렉토리를 `/ws` 로 설정.
- `--gpus all` : host GPU 전부를 컨테이너에 전달(YOLO 추론에 필요). *host voice 노드는 GPU 불필요.*
- `-e ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-0}` : 셸에 값이 있으면 그 값, 없으면 `0`. host·컨테이너가 같은 도메인이어야 서로 통신.
- `-e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp` : DDS 구현을 CycloneDDS 로 고정.
- `-e CYCLONEDDS_URI=file:///cyclonedds.xml` : CycloneDDS 설정 파일 경로(아래 `-v` 로 mount 한 파일).
- `-e PYTHONUNBUFFERED=1` : 파이썬 출력 버퍼링을 꺼 로그가 즉시 보이게.
- `-v host경로:컨테이너경로:ro` : host 파일/폴더를 컨테이너 안에 연결(`:ro`=읽기 전용).
  - `…/cyclonedds.xml:/cyclonedds.xml:ro` : DDS 설정 주입.
  - `…/yolo_container:/ws/src` : host 소스 mount → `.py` 를 고치면 컨테이너가 곧바로 봄.
  - `yolo_build:/ws/build`, `yolo_install:/ws/install` : named volume(도커가 관리하는 저장소)에 빌드 산출물 보관 → 재기동해도 유지, host 폴더를 더럽히지 않음.
  - `…/dev/bashrc:/root/.bashrc:ro` : 컨테이너 셸 진입 시 ROS 환경을 자동 source.
- `local/ros2-jazzy-yolo:dev-builder` : 실행할 이미지(태그 `dev-builder` 고정).
- `bash -c '…'` : 컨테이너가 뜨면서 실행할 명령. 내부 순서:
  - `set +u` : 미정의 변수 참조 에러를 끔(ROS setup 스크립트가 미정의 변수를 건드리기 때문).
  - `source /opt/ros/$ROS_DISTRO/setup.bash` : ROS 환경 로드.
  - `find /ws/build /ws/install -mindepth 1 -delete 2>/dev/null || true` : 이전 빌드 산출물을 싹 지움(clean build).
  - `colcon build --symlink-install --merge-install` : 워크스페이스 빌드. `--symlink-install`=산출물을 복사 대신 심링크(소스만 고치면 재빌드 없이 반영), `--merge-install`=install 을 패키지별로 쪼개지 않고 한 곳에 통합.
  - `sleep infinity` : **컨테이너를 계속 살려 두는 무한 대기.** 컨테이너는 메인 명령이 끝나면 종료되므로, 빌드만 하고 죽지 않도록 아무 것도 안 하며 영원히 기다려 `docker exec` 로 진입할 수 있는 상태를 유지.

빌드 완료까지 대기 → 진입:

```bash
docker logs -f yolo-detection                 # "Summary: N package finished" 뜨면 Ctrl+C
docker exec -it yolo-detection bash
```

**플래그 해설**

- `docker logs -f yolo-detection` : 컨테이너 stdout 을 실시간 tail(`-f`=follow). 빌드 로그를 보다 `Summary: N packages finished` 가 뜨면 빌드 완료 → `Ctrl+C`.
- `docker exec -it yolo-detection bash` : 떠 있는 컨테이너 안으로 셸 진입(`-i`=stdin 유지, `-t`=tty 할당 → 대화형).

컨테이너 안에서 노드 실행:

```bash
ros2 run object_detection object_detection    # Ctrl+C → host 에서 .py 수정 → 재실행
```

**플래그 해설**

- `ros2 run <pkg> <node>` : 패키지의 실행 노드(entry point) 하나를 실행.

**host voice 노드** — 컨테이너가 아니다. 마이크가 하드웨어에 종속돼(컨테이너 오디오 passthrough 가 머신마다 깨짐) host 에서 직접 실행한다. Python 스택은 `setup-app.sh` 의 `voice-host-install.sh` 가 host 에 이미 설치했다. ROS + 워크스페이스 overlay 를 켠 뒤 노드를 띄운다:

```bash
source ~/ros2_jazzy_test/resources/activate.sh      # ROS underlay + cobot_ws overlay
source ~/ros2_jazzy_test/resources/interaction.sh   # _load_env 등 헬퍼
_load_env ~/.config/cobot2/.env                     # OPENAI_API_KEY (STT/LLM 용)
ros2 run voice_processing get_keyword               # Ctrl+C → .py 수정 → 재실행
```

**해설**

- `source resources/activate.sh` : ROS2 + `~/cobot_ws/install` overlay 를 켜 `voice_processing` 패키지를 인식. langchain/openwakeword 는 host 에 직접 설치돼 있어(`voice-host-install.sh`) system python 이 그대로 본다 — venv 활성화 불요.
- `_load_env ~/.config/cobot2/.env` : `OPENAI_API_KEY` 를 프로세스 env 로 로드(STT=Whisper·LLM 호출에 필요). 이 `.env` 는 인스톨러가 만들지 않음 — `.env.example` 을 `~/.config/cobot2/.env` 로 복사 후 키 입력(레포 밖이라 커밋 위험 없음). wakeword 만 확인하면 생략 가능. `bringup.sh` 통합 실행은 이 로드를 대신 해 준다. `.env` 를 `source` 하지 않고 한 줄씩 파싱해 `KEY=VALUE` 만 export 한다 — `.env` 에 섞여 든 셸 명령이 실행되는 것을 막는다(`bringup.sh` 도 같은 함수를 쓴다).
- **마이크** : 데스크톱 세션의 PipeWire 기본 입력 장치를 그대로 사용한다(GUI 사운드 설정에서 고른 그것). 특정 장치를 강제하려면 `export VOICE_MIC_DEVICE=<hw:C,D 또는 sounddevice 인덱스>` 후 실행 — 컨테이너 때의 `asound.conf`/`/dev/snd` 하드코딩이 사라져 머신마다 재설정할 필요가 없다.

> yolo 컨테이너 정지·삭제: `docker rm -f <name>` (dev 빌드 볼륨까지 비우려면 `docker volume rm yolo_build yolo_install`). host voice 는 Ctrl+C(또는 `pkill -f get_keyword`)로 종료.

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

### 컨테이너 없이 실행해 보기 (교육용 대비)

컨테이너 사용 효과를 비교하려면 모놀리식 노드를 host venv 로 직접 실행하는 실습 가이드를 따른다:
[`scripts/venv-demo/LAB.md`](scripts/venv-demo/LAB.md). 의존성 설치·네임스페이스·멀티터미널 기동을
한 줄씩 직접 수행하며, 컨테이너(`bringup.sh` + `docker compose`)가 대신 처리하던 작업량을 체감한다.
정식 설치 경로가 아니라 비교 학습용이다.
