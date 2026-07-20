# 데모 venv 학생 배포/복구용 uv 설치 경로 — 설계

- 날짜: 2026-07-20
- 상태: 설계 승인됨 (구현 전)
- 관련: `scripts/venv-demo/LAB.md`(불변 유지), `docs/specs/2026-06-26-venv-pickplace-demo-design.md`

## 배경

데모 venv(`~/cobot_demo_ws/.venv`)는 corecode + `pick_and_place_voice` + `pick_and_place_text` 를 컨테이너 없이 실행하는 커리큘럼 자산. 설치가 순서 고정 + `--no-deps` 2건 + numpy<2 최후 재핀으로 복잡해, one-by-one(학습용)과 별개로 **학생 배포/복구용 원커맨드 경로**가 필요.

2026-07-10 에는 "깨짐 3문제가 tool-agnostic 이라 uv 로도 해결 불가"로 uv 전환을 기각했으나, 2026-07-20 실측(uv 0.11.2, py3.12)으로 기술 근거 3건 재검증 결과 **전부 해결 가능** 확인:

| 문제 | pip 방식 | uv 실측 결과 |
|---|---|---|
| openwakeword → tflite-runtime (py3.12 wheel 없음) | `--no-deps` + 수동 의존 | `[[tool.uv.dependency-metadata]]` 로 의존 선언 교체 → lock 에 tflite 0건, 설치·import 성공 |
| roboflow → opencv-python-headless 가 cv2/ 충돌 | `--no-deps` + 안전 의존 수동 | 동일 메커니즘으로 headless 제거 → cv2 단일 소유, `import roboflow` 성공 |
| ultralytics 가 numpy>=2 유발 | 최후 `--force-reinstall numpy<2` | `override-dependencies=["numpy<2"]` → resolver 수준 강제, 순서 무관 (1.26.4) |

추가 실측: `uv venv --system-site-packages` + `uv sync` 후 플래그 보존, torch `2.11.0+cu128` explicit index 로 lock 고정, 전체 118 패키지 단일 resolution. 당시 평가는 override(same-name 전용)만 보고 dependency-metadata(의존 선언 자체 교체)를 누락했던 것.

uv 로도 안 되는 것(도구 무관): tflite shim 생성, oww 모델 복사+TFL3 검증, apt 헤더 — wrapper 스크립트가 담당. system-site 로 공유되는 ROS 바인딩이 lock 밖인 구조적 상한은 pip 과 동일.

## 결정

- LAB.md one-by-one(학습)과 A4-fast 는 불변. **병행 경로**로 `scripts/venv-demo/uv/` 신설.
- 산출 venv 는 LAB 와 동일 사양: `~/cobot_demo_ws/.venv`, `--system-site-packages`, system python 3.12 기반.
- 접근 대안 비교: bash+pip 자동화(A안)는 범위 핀이라 학생별 설치 시점에 transitive drift → 배포용 재현성 미달로 기각. `uv pip compile` lock 배포(C안)는 `--emit-index-url` 이 cu128 인덱스를 못 실어(실측) 기각.

## 파일 구조 (신규 3파일)

```
scripts/venv-demo/uv/
├── pyproject.toml   # 전체 스택 선언: requirements.txt 활성 줄 + torch/torchvision(cu128)
│                    #   + dependency-metadata 2건(openwakeword 0.6.0 · roboflow)
│                    #   + [tool.uv] override-dependencies numpy<2
│                    #   + [[tool.uv.index]] pytorch-cu128 (explicit) + tool.uv.sources 핀
├── uv.lock          # 이 레포에서 `uv lock` 생성·커밋 — 학생 전원 동일 venv 의 근거
└── setup.sh         # 학생이 실행하는 유일한 명령
```

LAB.md 는 A4-fast 절에 포인터 1줄만 추가: 복구/배포용 원커맨드 = `bash uv/setup.sh` (학습용 아님).

## setup.sh 동작

`set -euo pipefail`, `[n/6]` 진행률, 멱등(재실행 = 복구, 별도 state 파일 없음 — uv/apt 멱등성 활용).

1. `[1/6]` 전제 확인 — `/usr/bin/python3.12` 존재, uv 존재. uv 없으면 **고정 버전 0.11.2** 설치(astral.sh 버전 핀 installer `https://astral.sh/uv/0.11.2/install.sh`)를 confirm 후 진행(무확인 자동 설치 금지).
2. `[2/6]` apt 헤더 — `portaudio19-dev libsndfile1 python3.12-venv` (기설치 시 skip).
3. `[3/6]` venv — `uv venv --python /usr/bin/python3.12 --system-site-packages ~/cobot_demo_ws/.venv` (존재 시 재사용).
4. `[4/6]` `uv sync --frozen --active` — venv 가 프로젝트 디렉토리 밖(`~/cobot_demo_ws/.venv`)이므로 VIRTUAL_ENV 설정 + `--active` 로 대상 지정, lock 그대로 전체 스택 설치.
5. `[5/6]` post-install — tflite_runtime shim 생성 + `resources/oww_models/` → openwakeword 설치 경로 복사 + TFL3 매직바이트 검증 (LAB A4 (5) 와 동일 내용, 기존재 시 skip).
6. `[6/6]` self-check — LAB A4 검증 블록과 동일 import 세트(numpy 1.x assert, cv2, torch, openwakeword, tflite_runtime shim, roboflow, pymodbus 등).

에러 처리: 단계 실패 시 `[FAIL] [n/6] <이유>` 출력 후 즉시 중단. 재실행하면 완료 단계는 자연 skip.

## lock 정책

- 갱신 절차: 이 레포에서 pyproject.toml 수정 → `uv lock` → 커밋. 학생 머신은 `--frozen` 전용(재해석 금지).
- `requirements.txt`(LAB)와 pyproject.toml 핀은 수동 동기 — 원천은 동일(컨테이너 Dockerfile 미러). 한쪽 갱신 시 다른 쪽 확인.
- `docs/COMPATIBILITY.md` 에 uv 0.11.2 행 추가.

## 검증 계획 / 배포 게이트

- 이 레포 머신: `shellcheck setup.sh` + uv-managed 3.12 로 sync 스모크(torch 제외 서브셋은 2026-07-20 기실측).
- **타깃(Ubuntu 24.04) 1회 실측 전 학생 배포 금지**: ① system 3.12 venv 를 `uv sync` 가 재생성 없이 재사용 ② torch cu128 실설치 ③ ROS 바인딩(rclpy) import — 3건 모두 통과가 게이트.

## Scope 제외

A2(ws 구성·voice 번들 rename·마이크 fix), LAB Part B/C(실행·teardown), corecode/cobot2 소스 배치 — 기존 절차 그대로.
