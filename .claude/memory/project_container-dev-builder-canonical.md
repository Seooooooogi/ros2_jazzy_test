---
name: container-dev-builder-canonical
description: 앱 컨테이너(yolo/voice) 이미지는 :dev-builder 단일 표준. :dev(runtime) 폐기 — 안내·설치에서 배제.
metadata:
  type: project
---

# 컨테이너 이미지 표준 = :dev-builder 단일 (2026-07-08 결정)

수업·운영에 쓰는 yolo/voice 앱 컨테이너 이미지는 `:dev-builder`(Dockerfile `builder` 스테이지) **단일 표준**. `:dev`(runtime 스테이지) 는 폐기.

**Why:** 수업 흐름이 소스 live-mount + 컨테이너 안 colcon build(= `docker-compose.dev.yml` / `bringup.sh` = dev-builder)로 통일됨. runtime `:dev` 는 이중 유지 부담만 남는 중복 경로.

**How to apply:**
- 컨테이너 실행/디버깅 안내에 `:dev`(runtime) 이미지를 **제안하지 않는다** — 항상 `:dev-builder`.
- 설치(`setup-app.sh` → `containers/build-all.sh`)는 이미 두 이미지를 `docker build --target builder` 로만 빌드 → `:dev` 를 애초에 안 만든다(배제 완료).
- `:dev`(runtime) 가 코드에 아직 남은 곳: `containers/docker-compose.yml` base 의 `:${VOICE_TAG:-dev}` / `:${YOLO_TAG:-dev}` 서비스 정의 + 각 Dockerfile `runtime` 스테이지 — install 이 호출 안 하는 수동 runtime/publish 경로(dormant). 정리는 보류(사용자 2026-07-08 "메모리만" 결정).

관련: `project_phase4-container-architecture.md`(corecode = 컨테이너 비적재, dev override recipe).
