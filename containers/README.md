# containers — Phase 4 애플리케이션 컨테이너 (yolo)

> voice(voice_processing)는 컨테이너가 아니라 **host 에서 직접 실행**한다 — 마이크 하드웨어 종속 때문. `resources/app-install.sh voice` 로 설치하고 `ros2 run voice_processing get_keyword` 로 띄운다(최상위 `README.md`). 이 디렉토리는 yolo 컨테이너만 다룬다.

- base 서비스 정의: `docker-compose.yml` — network/GPU/env. 단독 `up` 은 runtime(최종) 이미지·노드 자동 기동 경로(학습 기본 흐름은 이걸 빌드 안 함, 수동/publish 용 보존).
- 기본 통합 실행: `bash containers/bringup.sh` = base + `docker-compose.dev.yml`(dev-builder) 머지 — live-mount + 컨테이너 안 colcon build 후 노드 자동 기동. 이미지 빌드/검증은 `containers/build-all.sh`(builder 스테이지 = `:dev-builder`). 최상위 `README.md` 참조.
  - 컨테이너·host voice 를 띄운 뒤 마지막에 `ros2 launch m0609_rg2_bringup bringup.launch.py` 로 로봇 드라이버 + RG2 그리퍼 + RealSense 를 한 번에 올린다(별도 레포 `M0609_RG2_Integration` 의 패키지, `setup-app.sh` 가 `~/cobot2_ws/src` 로 심볼릭 링크).
  - launch 인자: `mode`(virtual|real, 기본 virtual) / `host`(기본 192.168.1.100, virtual 이면 127.0.0.1 강제) / `port`(12345) / `rt_host`(192.168.137.50) / `camera`(기본 false) / `rviz`(기본 true). `bringup.sh` 에 넘긴 인자는 그대로 전달된다.
  - `camera` 는 launch 기본이 false(standalone 개발 시 USB 카메라 미점유)지만, `bringup.sh` 는 사용자가 `camera:=` 를 명시하지 않으면 `camera:=true` 를 덧붙인다 — 이 래퍼는 yolo 컨테이너를 함께 띄우고 그 노드는 카메라 토픽이 없으면 조용히 대기만 하기 때문.
- 개발 모드(개별 수동): `docker-compose.dev.yml` — 코드 수정 live-mount + 노드 수동 기동(디버깅). 아래 설명.

## 개발 모드 (코드 수정 → 즉시 테스트)

프로덕션 컨테이너는 소스를 이미지에 구워(baked-in) 넣어 코드 수정 시 재빌드가 필요하다. dev 모드는 host 의 워크스페이스를 컨테이너 `/ws/src` 에 bind-mount 해 **수정이 즉시 반영**되고, 노드를 자동 기동하지 않아 **exec 로 들어가 직접 실행·디버깅**한다.

### 1) 워크스페이스 준비

`install.sh`(DSR 단계)가 통합 워크스페이스 `~/cobot2_ws` 를 레포에서 복사 생성한다 — 컨테이너 dev 모드가 mount 하는 서브디렉토리도 그 안에 포함된다(별도 생성 단계 불요).

- yolo = `~/cobot2_ws/src/cobot2/yolo_container`(od_msg + object_detection). voice 는 host 실행이라 dev mount 대상 아님.
- 이 서브디렉토리가 컨테이너 `/ws/src` 로 bind-mount 된다(서브디렉토리 자체가 패키지를 담아 중첩 src 없음).
- mount 경로는 `YOLO_WS` 로 변경 가능(기본 위 경로 — `config.sh` 단일 소스).
- **여기서 편집**한다. 레포 공유는 수정분을 레포 `cobot_ws/src/...` 로 되돌려 커밋.

### 2) 빌드 + 기동

```bash
DEV="-f containers/docker-compose.yml -f containers/docker-compose.dev.yml"
docker compose $DEV build              # builder 스테이지 = dev-builder 태그(프로덕션 이미지와 분리)
docker compose $DEV up -d yolo-detection
```

- 기동 시 mount 된 소스로 1회 `colcon build --symlink-install --merge-install` 후 대기(노드 자동 실행 안 함)

### 3) 진입해서 노드 수동 실행

```bash
docker exec -it yolo-detection bash
# (컨테이너 안 — ROS overlay 는 자동 source 됨)
ros2 run object_detection object_detection      # 수정 → Ctrl+C → 재실행 반복
```

voice 는 컨테이너가 아니다 — host 에서 `source resources/activate.sh` 후 `ros2 run voice_processing get_keyword`(마이크 = 데스크톱 PipeWire 기본, `VOICE_MIC_DEVICE` 로 override). 최상위 `README.md` 참조.

### 반영 규칙

- **`.py` 편집** → 노드 재시작만으로 반영(`--symlink-install` 이라 재빌드 불요).
- **`od_msg` 의 `.srv` 편집**(메시지) → codegen 이라 컨테이너 안에서 `colcon build` 재실행 필요.

### 전제 (프로덕션과 동일)

- `~/.config/cyclonedds/cyclonedds.xml` 렌더 완료(dds-tuning) — base compose 가 read-only mount.
- host voice: `.env` 의 `OPENAI_API_KEY`(bringup.sh 가 로드) + 데스크톱 마이크(PipeWire 기본).
- yolo: host 가 RealSense 토픽(`/camera/*`)을 publish 중이어야 추론 입력 존재. 그 publish 는 이제 통합 bringup 이 맡는다 — `bash containers/bringup.sh`(= `camera:=true` 자동 부여) 또는 `ros2 launch m0609_rg2_bringup bringup.launch.py camera:=true`. **토픽 경로가 바뀌었다**(2026-07-21): 새 launch 는 realsense2_camera_node 를 `namespace='/'` + `name='camera'` 로 띄워 `/camera/*` 를 낸다(이전 `/camera/camera/*` 의 중복 한 단계 제거). 스트림 설정(align_depth·enable_rgbd·enable_sync·pointcloud)은 그대로다. 소비자(`ImgNode`)는 `/camera/color/image_raw` 등 **절대 경로**를 구독하므로 기동 인자가 필요 없다(2026-07-22 — 한때 상대 이름 + `-r img_node:__ns:=/camera` 였으나, 인자를 빠뜨리면 에러 없이 토픽만 비어 되돌렸다. 그 인자를 그대로 줘도 결과는 같다). 컨테이너를 개별 수동 기동할 때는 카메라가 먼저 떠 있어야 한다.
