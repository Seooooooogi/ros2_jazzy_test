# backup/voice-processing — 폐기된 voice 컨테이너 레시피 (보존본)

- **무엇**: ADR-027(2026-07-08)로 폐기된 `containers/voice-processing/` 컨테이너 빌드 레시피.
- **왜 보존**: 롤백·참조용(사용자 요청 — "혹시 모르니 삭제 말고 보존"). `backup/` 은 main 제외(dev 전용)라 공개 installer 엔 안 실리고 dev 브랜치에만 남는다.
- **폐기 사유**: 마이크가 하드웨어 종속 — `asound.conf` 가 `hw:1,7`/`card 1` 하드코딩 + raw `/dev/snd` ALSA passthrough(미검증)라 사운드 하드웨어가 다른 머신에서 wakeword/STT 미인식. voice 는 host 직접 실행으로 이관(`resources/voice-host-install.sh`), yolo 는 컨테이너 유지.

## 여기 있는 것
- `Dockerfile` — voice-processing 이미지(멀티스테이지, base `ros:jazzy-ros-base-noble`). langchain/openai/openwakeword + ai-edge-litert shim + numpy<2.
- `asound.conf` — 컨테이너 ALSA 기본 캡처 매핑(`hw:1,7`/`card 1` — 이 하드코딩이 기종 종속의 주범).

## 여기 없지만 복구 가능한 것
- **feature 모델**(`oww_models/`): 삭제 아님 — `resources/oww_models/` 로 이전(host 설치가 사용). 살아 있음.
- **compose voice 서비스 / build-all voice 빌드·smoke / docker-compose.dev voice 서비스·볼륨 / setup-app OPENAI 키 위치**: 코드 커밋 `511406a`(feat/voice-host)에서 제거. 전체 diff = `git show 511406a`.
- **빌드된 로컬 이미지**(`*/ros2-jazzy-voice:dev-builder`): 이번 이관은 이미지를 지우지 않는다(레포 어디에도 `docker rmi` 없음). 실기에 그대로 존재 — 필요하면 그대로 재사용 가능.

## 롤백 방법
- 전체 되돌리기: `git revert 511406a` (feat/voice-host 에서) — voice 컨테이너 복원 + host 설치 제거.
- 레시피만 복원: `git checkout 511406a^ -- containers/voice-processing/`.
- **재빌드 시 주의**: 이 `Dockerfile` 은 `COPY containers/voice-processing/oww_models /tmp/oww_models` 를 참조하는데 모델이 `resources/oww_models/` 로 옮겨졌다 → 그 COPY 경로를 고치거나 모델을 원위치로 되돌려야 빌드된다.
