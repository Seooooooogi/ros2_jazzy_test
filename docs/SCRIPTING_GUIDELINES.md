# Shell Scripting Guidelines

설치 스크립트(`install.sh` / `a0N` / `resources/*.sh` / `containers/*.sh`) 작성·리팩토링 규약. 신규 스크립트는 아래 패턴을 따르면 기존 코드와 일관된다.

## 1. 실행 진입점 vs source 전용 라이브러리

| 구분 | `set -euo pipefail` | 예시 |
|---|---|---|
| **실행 진입점** (직접 `bash X.sh`) | **필수** (shebang 다음 줄) | `install.sh`, `a0N`, `resources/` 설치 본문(kernel-baseline, docker-install …) |
| **source 전용 라이브러리** (`source X.sh`) | **두지 않는다** | `config.sh`, `state.sh`, `run-step.sh`, `steps.sh`, `confirm.sh`, `env-load.sh`, `unattended.sh`, `activate.sh`, `apt-repo.sh` |

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
- 진행률 배너 `[n/total]` 는 `run-step.sh`(`run_step`)가 전담 — 본문에서 직접 출력하지 않는다.
- 변수: 전역/환경 = 대문자(`ROS_DISTRO`), 지역 = `local` 소문자, 내부 헬퍼 = `_` prefix.

## 6. 신규 설치 스크립트 템플릿
```bash
#!/usr/bin/env bash
# resources/<name>-install.sh — 한 줄 설명.
# 순수 설치 본문 — state 프레이밍은 오케스트레이터(run-step.sh)가 소유.
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
- step 추가 시 `resources/steps.sh` 의 스테이지 함수 + `STAGE_*_COUNT` 1곳만 갱신(install.sh/a0N 양쪽 자동 반영).
