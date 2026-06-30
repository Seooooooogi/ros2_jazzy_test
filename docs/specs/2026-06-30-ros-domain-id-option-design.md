# ROS_DOMAIN_ID 사용자 입력 옵션화 — 설계 (Design Spec)

- **날짜**: 2026-06-30
- **상태**: Draft (user review 대기)
- **관련**: `resources/config.sh` (단일 진실 소스), `resources/dds-tuning.sh` (`~/.bashrc` managed block), `containers/docker-compose.yml` (compose interpolation), ADR-016/ADR-020 (DDS/RMW)

---

## 1. 목적 (Goal)

현재 `ROS_DOMAIN_ID` 는 `resources/config.sh` 에서 `${ROS_DOMAIN_ID:-42}` 로 디폴트 **42 하드코딩**. env override 만 가능하고 설치 시 사용자가 정할 수단이 없다. 같은 모델 머신을 여러 대 설치할 때 **도메인 분리가 필요**(같은 LAN 에서 서로의 DDS 토픽을 보지 않게)하므로, 설치 시 대화형 prompt 로 값을 받아 영속화한다.

핵심 불변식 — **host(activate.sh / 인터랙티브 셸) 와 두 컨테이너(compose)가 동일한 값**을 봐야 discovery 성립. 따라서 단일 영속 저장소를 두고 `config.sh` 가 그것을 디폴트로 읽는다.

## 2. 비목표 (Non-goals)

- **CLI flag(`--domain-id`) 미도입** — 대화형 prompt 만(사용자 결정).
- **setup-app.sh 별도 prompt 없음** — config.sh 가 같은 파일을 읽으므로 컨테이너도 자동 일치.
- **compose 파일 구조 변경 없음** — 기존 `${ROS_DOMAIN_ID:-42}` interpolation 유지(config.sh 가 채운 env 를 그대로 수신).
- **문서 전수 갱신 아님** — 사용자 대면 핵심 위치만.

## 3. 확정된 사용자 결정

| 항목 | 결정 |
|------|------|
| 입력 방식 | **대화형 prompt 만** (CLI flag / env-only 제외) |
| 영속 저장 위치 | **XDG config dir** (`~/.config/ros2_jazzy_test/`) — runtime config 분류 |
| `--reset` 시 거동 | XDG 분류라 **보존** (installer state wipe 와 분리, config.sh:136 철학 일치) |
| 유효 범위 검증 | 정수 `0–232` (ROS2 유효 도메인 범위) |

## 4. 아키텍처

### 4.1 영속 저장
- 파일: `${XDG_CONFIG_HOME:-${HOME}/.config}/ros2_jazzy_test/ros_domain_id` — 정수 한 줄.
- CYCLONEDDS_XML 과 같은 XDG 루트 아래(`~/.config`) → runtime config 일관 분류. `install.sh --reset`(STATE_DIR wipe)에도 보존.

### 4.2 config.sh — 단일 소스 읽기 (우선순위: env > 파일 > 42)
- 경로 변수 신설(단일 소스):
  ```sh
  : "${ROS2_JAZZY_TEST_CONFIG_DIR:=${XDG_CONFIG_HOME:-${HOME}/.config}/ros2_jazzy_test}"
  ```
- 기존 166행 교체:
  ```sh
  _domain_file="${ROS2_JAZZY_TEST_CONFIG_DIR}/ros_domain_id"
  if [[ -z "${ROS_DOMAIN_ID:-}" && -r "${_domain_file}" ]]; then
      ROS_DOMAIN_ID="$(cat "${_domain_file}" 2>/dev/null)"
  fi
  export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-42}"
  ```
- 명시적 env(`ROS_DOMAIN_ID=N bash ...`)는 최우선 — 테스트/CI override 보존. 파일 부재 시 42 fallback.

### 4.3 prompt — `resources/interaction.sh::prompt_domain_id`
- 위치: `sudo_prime` 이 사는 `resources/interaction.sh`. install.sh 시작 단계(시작 confirm 부근, step 6 reboot 이전)에서 1회 호출 → "시작 시 대화형 입력 모음, 이후 자동 진행" 원칙 유지.
- 동작:
  1. 기존 파일값 있으면 그 값을, 없으면 42 를 prompt 디폴트로 표시(`[기본 N]`, Enter=유지).
  2. 입력 검증: 정수 `0–232` 아니면 재입력 요구.
  3. 확정값을 `mkdir -p "${ROS2_JAZZY_TEST_CONFIG_DIR}"` 후 `ros_domain_id` 파일에 기록.
- **멱등**: 파일에 값이 있어도 재실행 시 그 값을 디폴트로 보여주고 Enter 로 유지 가능 → 무한 재질문 없음.
- **비대화형(TTY 없음)**: prompt 생략 → 기존 파일값 또는 42 로 진행 + 경고 로그(install.sh 의 기존 non-interactive confirm-skip 패턴과 동일).

### 4.4 dds-tuning.sh — 인터랙티브 셸 영속
- `~/.bashrc` managed block(현재 `RMW_IMPLEMENTATION` / `CYCLONEDDS_URI` export)에 `export ROS_DOMAIN_ID=...` 한 줄 추가.
- dds-tuning 은 이미 config.sh 를 source(파일값 반영)하므로 `$ROS_DOMAIN_ID` 가 영속값 → 단일 소스 유지. install.sh step 8 시점엔 prompt(시작 단계)가 이미 파일을 기록한 상태라 순서 정합.

### 4.5 문서/예시 갱신 (핵심만)
- `.env.example` — `ROS_DOMAIN_ID` 주석을 "설치 시 prompt 로 선택, 기본 42, 단일 소스 = config.sh + `~/.config/ros2_jazzy_test/ros_domain_id`" 로.
- `README.md` — `ROS_DOMAIN_ID=42` 안내를 "설치 시 선택(기본 42)" 로 보정.
- `docs/COMPATIBILITY.md` — "기본 42" 항목에 "설치 시 prompt 선택" 부기.

## 5. 데이터 흐름

```
[install.sh 시작]
  → prompt_domain_id  ── 입력/검증 ──▶  ~/.config/ros2_jazzy_test/ros_domain_id  (정수)
        │
        ▼ (이후 모든 source)
   config.sh: ROS_DOMAIN_ID = env > 파일 > 42 (export)
        ├─▶ host activate.sh / 직접 source 한 셸
        ├─▶ dds-tuning.sh → ~/.bashrc managed block (인터랙티브 셸 영속)
        └─▶ containers/bringup.sh → compose interpolation → yolo/voice 컨테이너
```

## 6. Hard Rule 정합성

- **단일 진실 소스**: 값은 한 파일(`ros_domain_id`)에만 저장, 모든 소비처가 config.sh 경유 → distro 단일 소스 원칙과 동형.
- **멱등성**: prompt 는 기존값 디폴트 + 파일 덮어쓰기(같은 값이면 무변화), bashrc 는 managed block 재작성(기존 패턴).
- **진행률/resumable**: prompt 는 step 외부(시작 단계)라 `[n/10]` 카운트 불변.
- **No hardcoded secrets**: 도메인 ID 는 secret 아님 — 평문 저장 무방.

## 7. 검증 계획

- `shellcheck *.sh resources/*.sh` 통과.
- 단위 확인:
  - `ROS_DOMAIN_ID=7 bash -c 'source resources/config.sh; echo $ROS_DOMAIN_ID'` → `7` (env 최우선).
  - 파일에 `15` 기록 후 `bash -c 'source resources/config.sh; echo $ROS_DOMAIN_ID'` → `15` (파일).
  - 파일/​env 없음 → `42` (fallback).
- 통합: prompt 입력 → 파일 기록 → 새 셸 `~/.bashrc` 에서 `echo $ROS_DOMAIN_ID` 일치, compose `config` 로 컨테이너 env 동일 확인.

## 8. 변경 파일 목록

- `resources/config.sh` — 경로 변수 + 읽기 로직.
- `resources/interaction.sh` — `prompt_domain_id` 함수.
- `install.sh` — 시작 단계에서 `prompt_domain_id` 호출.
- `resources/dds-tuning.sh` — managed block 에 `ROS_DOMAIN_ID` export.
- `.env.example`, `README.md`, `docs/COMPATIBILITY.md` — 안내 보정.
