# containers — Phase 4 애플리케이션 컨테이너 (yolo / voice)

- 프로덕션 정의: `docker-compose.yml` — 노드 자동 기동, 배포 이미지(fetch/build). 사용법은 최상위 `README.md` 참조.
- 개발 모드: `docker-compose.dev.yml` — 코드 수정 live-mount + 노드 수동 기동(디버깅). 아래 설명.

## 개발 모드 (코드 수정 → 즉시 테스트)

프로덕션 컨테이너는 소스를 이미지에 구워(baked-in) 넣어 코드 수정 시 재빌드가 필요하다. dev 모드는 host 의 워크스페이스를 컨테이너 `/ws/src` 에 bind-mount 해 **수정이 즉시 반영**되고, 노드를 자동 기동하지 않아 **exec 로 들어가 직접 실행·디버깅**한다.

### 1) 워크스페이스 준비

`install.sh`(DSR 단계)가 통합 워크스페이스 `~/cobot_ws` 를 레포에서 복사 생성한다 — 컨테이너 dev 모드가 mount 하는 서브디렉토리도 그 안에 포함된다(별도 생성 단계 불요).

- yolo = `~/cobot_ws/src/cobot2_ws/yolo_ws`(od_msg + object_detection), voice = `~/cobot_ws/src/cobot2_ws/voice_ws`(voice_processing)
- 이 서브디렉토리가 컨테이너 `/ws/src` 로 bind-mount 된다(서브디렉토리 자체가 패키지를 담아 중첩 src 없음).
- mount 경로는 `YOLO_WS`/`VOICE_WS` 로 변경 가능(기본 위 경로 — `config.sh` 단일 소스).
- **여기서 편집**한다. 레포 공유는 수정분을 레포 `cobot_ws/src/...` 로 되돌려 커밋.

### 2) 빌드 + 기동

```bash
DEV="-f containers/docker-compose.yml -f containers/docker-compose.dev.yml"
docker compose $DEV build              # builder 스테이지 = dev-builder 태그(프로덕션 이미지와 분리)
docker compose $DEV up -d yolo-detection      # 또는 voice-processing — 각각 독립 기동
```

- 기동 시 mount 된 소스로 1회 `colcon build --symlink-install --merge-install` 후 대기(노드 자동 실행 안 함)

### 3) 진입해서 노드 수동 실행

```bash
docker exec -it yolo-detection bash
# (컨테이너 안 — ROS overlay·venv 는 자동 source 됨)
ros2 run object_detection object_detection      # 수정 → Ctrl+C → 재실행 반복
```

voice 는 `docker exec -it voice-processing bash` → `ros2 run voice_processing get_keyword`.

### 반영 규칙

- **`.py` 편집** → 노드 재시작만으로 반영(`--symlink-install` 이라 재빌드 불요).
- **`od_msg` 의 `.srv` 편집**(메시지) → codegen 이라 컨테이너 안에서 `colcon build` 재실행 필요.

### 전제 (프로덕션과 동일)

- `~/.config/cyclonedds/cyclonedds.xml` 렌더 완료(dds-tuning) — base compose 가 read-only mount.
- voice: `.env` 의 `OPENAI_API_KEY` + 마이크(`/dev/snd`).
- yolo: host 가 RealSense 토픽(`/camera/camera/*`)을 publish 중이어야 추론 입력 존재.
