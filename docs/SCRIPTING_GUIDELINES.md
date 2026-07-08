# Shell Scripting Guidelines

설치 스크립트(`install.sh` / `a0N` / `resources/*.sh` / `containers/*.sh`) 작성·리팩토링 규약. 신규 스크립트는 아래 패턴을 따르면 기존 코드와 일관된다.

## 1. 실행 진입점 vs source 전용 라이브러리

| 구분 | `set -euo pipefail` | 예시 |
|---|---|---|
| **실행 진입점** (직접 `bash X.sh`) | **필수** (shebang 다음 줄) | `install.sh`, `a0N`, `resources/` 설치 본문(kernel-baseline, docker-install …) |
| **source 전용 라이브러리** (`source X.sh`) | **두지 않는다** | `config.sh`, `orchestrate.sh`(state + run_step + step 정의), `interaction.sh`(env-load + confirm + resume autostart), `activate.sh`, `apt-repo.sh` |

- sourced 파일에 `set -e` 를 넣으면 **호출자 셸 옵션을 오염**시킨다(호출 셸 전체가 errexit). 셸 옵션은 호출 진입점이 소유한다.
- source 전용 라이브러리는 헤더 주석에 `# source 전용 라이브러리 — set -euo 를 여기 두지 않는다(호출 진입점이 셸 옵션을 소유).` 한 줄 명시.

## 2. shebang / shellcheck
- shebang 은 항상 `#!/usr/bin/env bash` (시스템 경로 독립).
- 머지 전 `shellcheck *.sh resources/*.sh containers/*.sh` exit 0 필수. `SC1091`(source 미추적)은 `# shellcheck source=<path>` 주석으로 해소.

## 3. 멱등 가드 (Idempotency)
같은 스크립트를 N회 실행해도 결과 동일. 상황별 권장 가드:

| 상황 | 가드 |
|---|---|
| apt 패키지 설치 여부 | `dpkg -s <pkg> >/dev/null 2>&1` (root 불요·빠름) |
| CLI 도구 존재 | `command -v <cmd> >/dev/null 2>&1` |
| 파일 존재 | `[[ -f <file> ]]` |
| 파일 내용 조건부 기록 | `[[ -f <f> ]] && grep -qxF "<line>" <f>` (단일행) / `[[ "$(cat <f>)" == "$desired" ]]` (다중행) |
| apt hold 중복 | `apt-mark showhold \| grep -qx <pkg>` |

- `apt-get install -y` 자체는 이미 설치 시 no-op 이라 단순 패키지는 가드 없이 둬도 멱등. `dpkg -s` 가드는 재실행 시 apt 캐시 갱신을 건너뛰어 더 빠를 때만 추가.

## 4. apt repo + keyring 등록 — `add_apt_repo`
새 외부 apt repo 는 직접 키링/list 코드를 쓰지 말고 `resources/apt-repo.sh` 의 `add_apt_repo` 를 쓴다(키링 dir 보장 + 키 다운로드 + `chmod a+r` + list 멱등 기록 + `apt-get update` 중앙화).

```bash
source "${SCRIPT_DIR}/apt-repo.sh"
add_apt_repo \
    --mode dearmor --downloader curl \
    --key-url  "https://example.com/key.gpg" \
    --key-file "${KEYRING_DIR}/example.gpg" \
    --list-file "/etc/apt/sources.list.d/example.list" \
    --list-line "deb [signed-by=${KEYRING_DIR}/example.gpg] https://example.com/repo ${UBUNTU_CODENAME} main"
```

- `--mode raw` = 키를 그대로 저장(`.asc`/원본), `--mode dearmor` = `gpg --dearmor` 변환. **키 파일명·signed-by 경로는 vendor 형식 그대로** — 임의로 `.asc`↔`.gpg` 바꾸지 않는다(signed-by 경로가 깨진다).
- 선행 도구 설치(`apt install ca-certificates curl …`)는 vendor 마다 달라 `add_apt_repo` 밖, 각 스크립트에 둔다.
- 새 repo 도입 시 `docs/COMPATIBILITY.md` 매트릭스도 갱신.

## 5. 메시지 / 로그
- 콘솔 메시지는 `<script>: <msg>` prefix (예: `docker: ...`, `voice: ...`, `dsr: ...`). 어느 step 출력인지 식별.
- 경고·에러는 `>&2`(stderr). 진행 정보는 stdout(로그 파일로 분리됨).
- 진행률 배너 `[n/total]` 는 `orchestrate.sh`(`run_step`)가 전담 — 본문에서 직접 출력하지 않는다.
- 변수: 전역/환경 = 대문자(`ROS_DISTRO`), 지역 = `local` 소문자, 내부 헬퍼 = `_` prefix.

## 6. 신규 설치 스크립트 템플릿
```bash
#!/usr/bin/env bash
# resources/<name>-install.sh — 한 줄 설명.
# 순수 설치 본문 — state 프레이밍은 오케스트레이터(orchestrate.sh 의 run_step)가 소유.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

# 1) 전제/멱등 가드.
if command -v <tool> >/dev/null 2>&1; then
    echo "<name>: <tool> 이미 설치됨 — skip"
    exit 0
fi

# 2) 작업.
sudo apt-get update
sudo apt-get install -y <package>

echo "<name>: success — <작업> 완료"
```
- step 추가 시 `resources/orchestrate.sh` 의 스테이지 함수 + `STAGE_*_COUNT` 1곳만 갱신(install.sh/a0N 양쪽 자동 반영).
- 함수 주석 — 비자명 함수는 Google `####` 블록(해당되는 `Globals`/`Arguments`/`Outputs`/`Returns` 섹션만), 사소한 헬퍼는 한 줄:

```bash
#######################################
# 단계 하나를 실행하고 성공/실패를 state 에 기록.
# Globals:
#   STATE_FILE
# Arguments:
#   $1 - 단계 이름
#   $2.. - 실행할 명령
# Returns:
#   명령의 종료 코드
#######################################
run_step() { ...; }

# 사소한 헬퍼는 한 줄.
_ts() { ...; }
```

## 7. 한 도메인 = 여러 step → 서브커맨드 dispatch
같은 vendor/도메인이 여러 step 으로 나뉘면(예: ROS2 desktop+extras, RealSense sdk+ros) 파일을
나누는 대신 **한 파일 + 서브커맨드 dispatch** 로 묶는다. 각 step 은 여전히 별도 프로세스
(`bash <file>.sh <sub>`)로 실행돼 `set -euo` 진입점 분리와 run_step 진행률/resume key 독립이
유지된다(`ros2-packages.sh desktop|extras`, `realsense-install.sh sdk|ros`).

```bash
case "${1:?<name>: subcommand 필요 (a|b)}" in
    a) do_a ;;
    b) do_b ;;
    *) echo "<name>: 알 수 없는 subcommand '$1' (a|b)" >&2; exit 2 ;;
esac
```
- `orchestrate.sh` 의 `run_step` 줄에 서브커맨드를 인자로 넘긴다: `bash "${RESOURCE_DIR}/<file>.sh" a`.
- 서브커맨드 분기 안에서만 쓰는 변수는 해당 함수 `local` 로 — branch 간 누수 차단.

## 8. 주석 스타일
- **언어** — 주석 본문은 한글. 식별자·경로·플래그·env 이름·`# shellcheck` 지시어·`echo` 출력 문자열은 영어 그대로(한글화 금지).
- **함수 주석**:
    - 비자명 함수 → Google `####` 블록(`#######################################` 구분선). 해당되는 섹션만 나열: `Globals:` / `Arguments:` / `Outputs:` / `Returns:`. 없는 섹션에 `None` 채우지 않음.
    - 자명·짧은 헬퍼 → 한 줄 주석.
    - `# Public:` / `# Internal:` 태그 안 씀 — 설명이 의도를 담고, `_` prefix 가 내부(private) 신호.
- **인라인 주석**:
    - 난이도 = 초심자 기준. jargon(전문 용어) 첫 등장 시 한글 부연(예: "errexit(`set -e` — 실패 시 즉시 중단)").
    - rationale(왜 이렇게 했나)는 **삭제 금지** — plain 서술로 풀어서 유지.
- **규칙 번호 인용 금지** — ADR 번호·Hard Rule #N·Tier·내부 Phase 번호를 주석에 박지 않음(재정렬·삭제로 stale 됨). 대신 그 규칙의 **이유·사실을 직접 서술**(예: ❌ "Hard Rule #6" → ✅ "sourced `set -e` 는 호출자 셸을 오염").
- **source 전용 라이브러리 헤더** — §1 문구 그대로: `# source 전용 라이브러리 — set -euo 를 여기 두지 않는다(호출 진입점이 셸 옵션을 소유).`
