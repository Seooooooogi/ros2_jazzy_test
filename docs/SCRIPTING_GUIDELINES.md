# Shell Scripting Guidelines

설치 스크립트(`install.sh` / `setup-app.sh` / `resources/*.sh` / `containers/*.sh`) 작성·리팩토링 규약. 아래 패턴을 따르면 기존 코드와 일관된다.

## 1. 실행 진입점 vs source 전용 라이브러리

| 구분 | `set -euo pipefail` | 예시 |
|---|---|---|
| **실행 진입점** (직접 `bash X.sh`) | **필수** (shebang 다음 줄) | `install.sh`, `setup-app.sh`, `resources/{base-install,app-install,hostcfg}.sh` |
| **source 전용 라이브러리** (`source X.sh`) | **두지 않는다** | `config.sh`(버전 핀), `lib.sh`(state + run_step + step 정의 + confirm/autostart + apt repo 등록), `activate.sh` |

- sourced 파일에 `set -e` 를 넣으면 **호출자 셸 옵션을 오염**시킨다(호출 셸 전체가 errexit). 셸 옵션은 호출 진입점이 소유한다.
- source 전용 라이브러리는 헤더 한 줄에 `source 전용` 임을 밝힌다 — 읽는 사람이 `set -euo` 부재를 빠뜨린 것으로 오해하지 않게.

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
새 외부 apt repo 는 직접 키링/list 코드를 쓰지 말고 `resources/lib.sh` 의 `add_apt_repo` 를 쓴다(키링 dir 보장 + 키 다운로드 + `chmod a+r` + list 멱등 기록 + `apt-get update` 중앙화). `base-install.sh` / `app-install.sh` 는 파일 최상단에서 이미 `lib.sh` 를 source 하므로 함수 안에서 그냥 호출하면 된다. `hostcfg.sh` 는 `config.sh` 만 source 하므로, 거기에 apt repo 를 쓰는 단계를 추가한다면 `lib.sh` source 를 먼저 넣는다 — 없으면 `add_apt_repo: command not found` 로 죽는다.

```bash
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
- 콘솔 메시지는 `<step>: <msg>` prefix (예: `docker: ...`, `dds-tuning: ...`, `realsense-sdk: ...`). 한 파일이 여러 step 을 담으므로 prefix 는 파일명이 아니라 **step 이름**이다 — 로그만 보고 어느 step 출력인지 알 수 있어야 한다.
- 경고·에러는 `>&2`(stderr). 진행 정보는 stdout(로그 파일로 분리됨).
- 진행률 배너 `[n/total]` 는 `lib.sh`(`run_step`)가 전담 — 본문에서 직접 출력하지 않는다.
- 변수: 전역/환경 = 대문자(`ROS_DISTRO`), 지역 = `local` 소문자, 내부 헬퍼 = `_` prefix.

## 6. 설치 단계 추가하기
새 설치 단계는 **새 파일을 만들지 않는다**. 성격에 맞는 기존 스크립트에 함수로 넣고 `case` 에 서브커맨드를 등록한다.

| 성격 | 파일 |
|---|---|
| 재부팅 앞뒤 시스템 계층(커널·드라이버·런타임·apt 패키지) | `resources/base-install.sh` |
| 워크스페이스·앱 계층(드라이버 소스·SDK·python·빌드·컨테이너) | `resources/app-install.sh` |
| 설치 후 호스트 런타임 설정 | `resources/hostcfg.sh` |

```bash
# <무엇을 하는지 한 줄>. <왜 이 방식인지 한 줄 — 필요할 때만>
base_<name>() {
    local <파일 안에서만 쓰는 상수>="..."

    # 1) 전제/멱등 가드.
    if command -v <tool> >/dev/null 2>&1; then
        echo "<name>: <tool> 이미 설치됨 — skip"
        exit 0
    fi

    # 2) 작업.
    sudo apt-get update
    sudo apt-get install -y <package>

    echo "<name>: success — <작업> 완료"
}
```

- 함수 이름은 서브커맨드가 드러나게 짓는다(`base_kernel` / `ros2_desktop` / `app_colcon` / `hostcfg_dds`). 내부 헬퍼만 `_` prefix.
- **파일 최상단에 상수를 두지 않는다.** 한 파일에 여러 서브커맨드가 살아서 이름이 겹치고, `set -u` 아래에서 남의 변수를 보게 된다. 함수 안 `local` 로 둔다. 여러 step 이 공유하는 버전 핀만 `config.sh` 로 올린다.
- 서브커맨드는 별도 프로세스로 실행되므로 실패 시 `exit` 이 맞다. `return` 으로 바꾸지 않는다.
- 단계를 install.sh 시퀀스에 넣으려면 `resources/lib.sh` 의 스테이지 함수 + `STAGE_*_COUNT` 1곳만 갱신한다.
- **state 키(`run_step` 의 두 번째 인자)는 한 번 정하면 바꾸지 않는다.** 설치를 진행 중인 머신이 완료 단계를 다시 돈다.

## 7. 한 도메인 = 여러 step → 서브커맨드 dispatch
같은 vendor/도메인이 여러 step 으로 나뉘면(예: ROS2 desktop+extras, RealSense sdk+ros) 파일을
나누는 대신 **한 파일 + 서브커맨드 dispatch** 로 묶는다. 각 step 은 여전히 별도 프로세스
(`bash <file>.sh <sub>`)로 실행돼 `set -euo` 진입점 분리와 run_step 진행률/resume key 독립이
유지된다(`base-install.sh ros2-desktop|ros2-extras`, `app-install.sh realsense-sdk|realsense-ros`).

```bash
case "${1:?<name>: subcommand required (a|b)}" in
    a) do_a ;;
    b) do_b ;;
    *) echo "<name>: unknown subcommand '$1'" >&2; exit 2 ;;
esac
```
- `lib.sh` 의 `run_step` 줄에 서브커맨드를 인자로 넘긴다: `bash "${RESOURCE_DIR}/<file>.sh" a`.
- 서브커맨드 분기 안에서만 쓰는 변수는 해당 함수 `local` 로 — branch 간 누수 차단.

## 8. 주석 스타일
- **언어** — 주석 본문은 한글. 식별자·경로·플래그·env 이름·`# shellcheck` 지시어·`echo` 출력 문자열은 영어 그대로(한글화 금지).
- **분량** — 블록당 무엇을 하는지 한 줄 + 왜 그런지 한 줄. 두 줄로 안 되면 코드가 복잡한 것이지 주석이 모자란 것이 아니다.
- **함수 주석** — 함수 위 한두 줄. 밖에서 불리는 헬퍼는 `# 사용법:` 한 줄을 덧붙이고(`confirm_or_abort` / `sudo_prime`), 인자가 많아 호출 형태가 한눈에 안 들어오는 `add_apt_repo` 만 여러 줄 사용법 블록을 둔다. Google `####` 블록(`Globals:`/`Arguments:`/`Outputs:`/`Returns:`)은 쓰지 않는다. 인자는 함수 첫 줄의 `local a="$1" b="$2"` 가 이미 보여주고, 목록을 따로 두면 코드와 어긋난 채 남는다. `# Public:` / `# Internal:` 태그도 안 씀 — `_` prefix 가 내부(private) 신호.
- **독자 수준** — 전공 지식은 있으나 이 도메인은 처음인 사람. 도메인 용어(RMW, DDS discovery, HWE 커널, DKMS, colcon overlay)는 첫 등장 시 한 번만 부연한다. bash 관용구(`set -euo pipefail`, `:=`, `${VAR:?}`)는 설명하지 않는다.
- **rationale** — 한 줄로 압축해 남긴다. 사고 경위를 문단으로 적지 않는다. 자세한 배경은 `docs/` 쪽 문서가 담당한다.
- **`docs/...` 링크를 주석에 넣지 않는다** — `docs/` 는 `main` 트리에 없어 공개 브랜치에서 죽은 참조가 된다. 근거를 직접 서술한다.
- **폐기된 구조의 이력을 적지 않는다** — "구 XXX 였고 …로 옮김" 류. 지금 무엇인지만 적는다.
- **규칙 번호 인용 금지** — ADR 번호·Hard Rule #N·Tier·내부 Phase 번호를 주석에 박지 않음(재정렬·삭제로 stale 됨). 대신 그 규칙의 **이유·사실을 직접 서술**(예: ❌ "Hard Rule #6" → ✅ "sourced `set -e` 는 호출자 셸을 오염").
- **source 전용 라이브러리 헤더** — §1 대로 헤더 한 줄에 `source 전용` 임을 밝힌다. 정해진 문구를 통째로 복사해 붙이지는 않는다.
