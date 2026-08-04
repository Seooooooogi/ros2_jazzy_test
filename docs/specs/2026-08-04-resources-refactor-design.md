# resources/ 셸 스크립트 병합 + 주석 다이어트 — 설계 (design spec)

- **작성일**: 2026-08-04
- **상태**: 승인됨 (구현 대기)
- **기준 브랜치**: `main` (원격 `origin/main`). 착수 전 `fix/dsr-clone-pin` 의 미승격 4커밋을 main 으로 승격한다
- **산출 브랜치**: `refactor/resources-merge` (base `main`) — 코드. 문서·검증 하네스는 dev 브랜치(§3)
- **변경 파일**: `resources/*.sh` 18개 → 6개, `install.sh`, `setup-app.sh`, `containers/bringup.sh`, `containers/README.md`, `README.md`

## 1. 목적 (motivation)

`origin/main` 의 `resources/` 는 18파일 2063줄이고 그중 **993줄(48%)이 주석**이다. 주석 상당수는 한 결정의 배경을 문단으로 서술한 것이고, 같은 내용이 `docs/BASE_INSTALL_MANUAL.md`·`TROUBLESHOOTING.md`·`COMPATIBILITY.md`·`decisions/README.md` 에 이미 있다. 파일이 잘게 쪼개져 있어 한 단계를 따라가려면 파일 3~4개를 오간다.

우선순위는 **① 셸 파일 병합 ② 코드 길이 최소화** 두 가지다. 기능 추가·동작 변경은 하지 않는다.

## 2. 스코프

**포함**
- `resources/` 18파일 → 6파일 병합
- `setup-app.sh` 의 단계 러너 중복 구현 제거 (`lib.sh` 재사용)
- `install.sh` / `setup-app.sh` 주석을 같은 기준으로 정리
- `README.md` 에서 워크스페이스 rename 전환 안내 삭제
- `containers/bringup.sh` · `containers/README.md` 의 파일명 참조 갱신

**비포함 (non-goal)**
- `containers/*.sh` 의 그 외 부분, `scripts/*.sh` — 손대지 않는다
- 기능 추가 / 동작 변경 — 특히 `setup-app.sh` 에 재개(state) 기능을 새로 넣지 않는다
- `config.sh` / `activate.sh` 의 경로·변수명 변경 — 외부 계약이다
- `docs/` 의 파일명 참조 갱신 — main 트리에 `docs/` 가 없으므로 dev 브랜치 작업으로 분리한다(§3)
- `docs/MIGRATION_NOTES.md`, `docs/specs/`, `docs/plans/`, `docs/decisions/` — 불변 기록이라 당시 파일명을 유지한다

## 3. 브랜치 모델

`main` 은 타 머신 공개 설치 검증용 브랜치이고, `.claude-main-exclude` 에 따라 `docs/` · `scripts/` · `CLAUDE.md` · `.claude/` · `tasks/` · `backup/` · `containers/template/` 이 **트리에 없다**. `.github/workflows/guard-internal-paths-on-main.yml` 이 main 대상 push·PR 에서 이를 검사해 실패시킨다.

또 `README.md` 는 `.main-keep-ours` 등록 파일이라 `merge-to-main.sh:78-85` 가 머지 직후 main 버전을 무조건 복원한다 — **dev 브랜치에서 README 를 고치면 main 에 영원히 도달하지 않는다**. README 를 실제로 바꾸려면 main 기준 브랜치에서 편집해야 한다.

따라서 작업을 두 브랜치로 나눈다.

| 브랜치 | base | 담는 것 |
|---|---|---|
| `refactor/resources-merge` | `main` | `resources/*.sh`, `install.sh`, `setup-app.sh`, `containers/bringup.sh`, `containers/README.md`, `README.md` |
| `fix/dsr-clone-pin` (dev) | 기존 | 이 spec, `scripts/trace-steps.sh`(§6.3), `docs/*` 참조 갱신, `CLAUDE.md` 갱신 |

**통합 경로**: `refactor/resources-merge` → `main` 직접 머지(이미 main 기준이라 제외 경로가 섞이지 않는다) → dev 가 `git merge main` 으로 되받는다. 이 순서라면 dev 의 문서 갱신이 리팩토링된 파일명을 가리키게 된다.

### 3.1 착수 전 선행 조건

`origin/main` 에는 `fix/dsr-clone-pin` 의 4커밋(`68ca849` `c2e4b46` `eee5550` `bbe4c5f`)이 아직 없다. 그중 둘이 이 리팩토링의 대상 파일을 건드린다.

| 파일 | `origin/main` | `fix/dsr-clone-pin` |
|---|---|---|
| `resources/config.sh` | 206줄, `DSR_REPO_URL`/`DSR_COMMIT` 없음 | 212줄, 커밋 핀 있음 |
| `resources/dsr-project-install.sh` | 93줄, 브랜치 clone | 80줄, 커밋 핀 clone (재작성) |

승격하지 않고 시작하면 옛 `dsr-project-install.sh` 를 `app-install.sh` 로 흡수하게 되고, 나중에 4커밋을 올릴 때 파일이 사라져 있어 modify/delete 충돌이 난다. 그래서 **먼저 승격한다**.

```bash
git checkout fix/dsr-clone-pin
bash scripts/merge-to-main.sh fix/dsr-clone-pin
bash scripts/check-no-claude-on-main.sh main
git push origin main
git checkout -b refactor/resources-merge main
```

`install.sh` · `setup-app.sh` · `containers/bringup.sh` · `README.md` 는 main 과 dev 가 동일하므로 승격 후에도 그대로다.

## 4. 파일 경계

| 새 파일 | 흡수 대상 | 성격 |
|---|---|---|
| `config.sh` | (그대로) | **공개 API** — `~/.bashrc`, docker compose, `containers/bringup.sh:39` 가 source. 경로·변수명 불변 |
| `activate.sh` | (그대로) | **공개 API** — `README.md`, `containers/README.md`, `setup-app.sh` 안내문이 참조. 경로 불변 |
| `lib.sh` | `orchestrate.sh` + `interaction.sh` + `apt-repo.sh` | source 전용 라이브러리 |
| `base-install.sh` | `kernel-baseline.sh`, `nvidia-driver-install.sh`, `docker-install.sh`, `ros2-packages.sh`, `vscode-install.sh` | `install.sh` 가 호출 |
| `app-install.sh` | `dsr-project-install.sh`, `realsense-install.sh`, `voice-host-install.sh`, `colcon-build.sh`, `nvidia-container-toolkit-install.sh` | `setup-app.sh` 가 호출 |
| `hostcfg.sh` | `dds-tuning.sh`, `network-static-ip.sh` | `install.sh` step 8·9 |

`install-resume-launcher.sh` 는 §5.4 방식으로 `install.sh` 에 흡수한다.

`resources/` 의 비-셸 자산 **`cyclonedds.xml.in`** · **`sysctl-cyclonedds.conf`** · **`oww_models/`** 는 그대로 둔다. 각각 `hostcfg.sh dds` 와 `app-install.sh voice` 가 읽고, `scripts/venv-demo/` 도 `oww_models/` 를 참조한다 — 경로가 바뀌면 실습 환경이 깨진다.

**디스패치 방식**: `ros2-packages.sh` 가 이미 쓰는 `bash <파일> <서브커맨드>` 패턴을 그대로 확장한다. 서브커맨드마다 별도 프로세스로 실행되므로 지금과 같은 실패 격리·재개 단위가 유지된다.

### 4.1 서브커맨드 매핑

`base-install.sh` — 괄호 안이 **state 키**이며 그대로 보존해야 재개가 깨지지 않는다.

| 서브커맨드 | 현재 파일 | state 키 |
|---|---|---|
| `kernel` | `kernel-baseline.sh` | `a01_kernel_baseline` |
| `nvidia` | `nvidia-driver-install.sh` | `a01_nvidia_driver` |
| `docker` | `docker-install.sh` | `a01_docker` |
| `ros2-desktop` | `ros2-packages.sh desktop` | `a01_ros2_desktop` |
| `ros2-extras` | `ros2-packages.sh extras` | `a01_ros2_extras` |
| `vscode` | `vscode-install.sh` | `a03_vscode` |

`hostcfg.sh`

| 서브커맨드 | 현재 파일 | state 키 |
|---|---|---|
| `dds` | `dds-tuning.sh` | `dds_tuning` |
| `network` | `network-static-ip.sh` | `network_static_ip` |

`app-install.sh` — `setup-app.sh` 는 state 를 쓰지 않으므로 state 키가 없다.

| 서브커맨드 | 현재 호출 |
|---|---|
| `dsr` | `dsr-project-install.sh` |
| `realsense-sdk` | `realsense-install.sh sdk` |
| `realsense-ros` | `realsense-install.sh ros` |
| `voice` | `voice-host-install.sh` |
| `colcon` | `colcon-build.sh` |
| `toolkit` | `nvidia-container-toolkit-install.sh` |

state 키는 `run_step` 의 두 번째 인자이므로 파일이 합쳐져도 이름만 그대로 두면 기존 state 파일과 호환된다. `a01_reboot` 는 `install.sh` 인라인이라 무변경.

## 5. 파일별 변경

### 5.1 `resources/lib.sh`

세 라이브러리를 합치면서 중복을 제거한다.

- `step_end_ok` / `step_end_fail` / `step_end_skip` 3함수 → `step_end <status>` 1개. 호출자가 `install.sh` 뿐이라 안전하다.
- `run_step` 과 `run_step_skip` 의 skip 판정 중복 통합.
- `print_copyright()` — `install.sh:83` 과 `setup-app.sh:66` 에 중복 정의된 것을 여기 1개로.
- **`STEP_STATE` 가드 신설**: 기본 1. `0` 이면 `run_step` 이 state 기록·skip 판정을 건너뛰고 배너·로그·heartbeat·실패 종료만 한다. `setup-app.sh` 가 이 모드를 쓴다 — 현재 동작(재실행 시 항상 전 단계 실행)을 그대로 보존하기 위한 것이지 기능 추가가 아니다.

**이름을 유지하는 공개 함수**: `run_step` `run_step_skip` `step_begin` `step_should_skip` `state_dump` `install_steps_total` `run_stage_a01` `run_stage_a03` `add_apt_repo` `confirm_or_abort` `confirm_or_abort_assumable` `register_resume_autostart` `remove_resume_autostart` `sudo_prime`. `config_assert_set` 은 `config.sh` 에 그대로 둔다.

### 5.2 `resources/base-install.sh` / `app-install.sh` / `hostcfg.sh`

- 파일당 헤더 + `source config.sh` + `config_assert_set` 보일러플레이트가 13벌 → 3벌로 준다.
- 각 설치 본문은 함수로 옮기고 파일 끝에서 `case "$1"` 디스패치. `ros2-packages.sh:155-159` 와 같은 형태.
- 본문 로직은 그대로 옮긴다. 명령·순서·조건 분기를 바꾸지 않는다.

### 5.3 `setup-app.sh`

- `step()` / `_hb()` / `run()` (100–169줄, 70줄) 삭제 → `lib.sh` 의 `run_step` 사용, `STEP_STATE=0`.
- `print_copyright()` 삭제 → `lib.sh` 것 사용.
- `do_workspace` / `do_containers` 의 호출을 새 서브커맨드로 교체.
- `obtain_cobot2` / `obtain_m0609` 는 그대로 둔다 — 설치 본문이 아니라 "소스를 어디서 가져오는가" 정책이고, 교체 지점이 한 함수로 격리돼 있어야 한다.

### 5.4 `install.sh` — `--resume-terminal`

`install-resume-launcher.sh` 를 없애고 `install.sh` 에 플래그로 흡수한다.

```bash
--resume-terminal)
    cd "${SCRIPT_DIR}"
    bash "$0"; rc=$?
    echo; echo "[resume] install.sh exited (${rc}). Keeping this terminal open."
    stty sane 2>/dev/null || true
    exec bash ;;
```

`register_resume_autostart` 의 `Exec` 라인은 대상만 바꾼다:

```
Exec=gnome-terminal -- bash "<repo>/install.sh" --resume-terminal
```

**인라인 셸(`bash -c '...'`)을 쓰지 않는 이유**: desktop entry 규격은 `Exec` 값에서 작은따옴표를 인용 문자로 인정하지 않아 인자가 공백에서 쪼개진다. 재개 UX 는 GUI 로그인이 있어야 검증되므로 조용히 깨지면 발견이 늦다. 위 형태는 현재(`gnome-terminal -- bash "<launcher>"`)와 인용 구조가 같아 위험이 없다.

`--resume-terminal` 은 `usage()` 에 노출하지 않는다 — autostart 전용 내부 플래그다.

### 5.5 `containers/bringup.sh` · `containers/README.md`

- `containers/bringup.sh:167` 의 안내 문구 `bash resources/voice-host-install.sh` → `bash resources/app-install.sh voice`. 이 파일에서 바꾸는 것은 이 한 줄뿐이다.
- `containers/README.md` 의 `resources/voice-host-install.sh` 참조(3줄) 갱신. 43줄의 `source resources/activate.sh` 는 경로가 안 바뀌므로 그대로 둔다.

### 5.6 `README.md`

33–35줄의 `~/cobot_ws` → `~/cobot2_ws` 전환 안내를 삭제한다. 구 이름으로 이미 빌드해 둔 머신을 위한 임시 메모라 신규 설치자에게는 잡음이다.

나머지 블록(`docker run` 원샷, RealSense 수동 기동)은 유지한다.

68줄·75줄의 `source ~/ros2_jazzy_test/resources/config.sh` 는 경로가 안 바뀌므로 그대로 둔다.

**이 파일은 main 기준 브랜치에서만 고칠 수 있다**(§3).

### 5.7 dev 브랜치 몫 — 문서 참조 갱신

main 트리에 없으므로 `fix/dsr-clone-pin` 에서 별도로 처리한다. 대부분 기계적 치환이다.

| 파일 | 참조 수 |
|---|---|
| `docs/COMPATIBILITY.md` | 42 |
| `docs/DEVELOPMENT_ROADMAP.md` | 10 |
| `docs/TROUBLESHOOTING.md` | 5 |
| `docs/CONTAINER_VS_HOST.md` | 3 |
| `docs/SCRIPTING_GUIDELINES.md` | 2 |
| `docs/TRAINEE_PRACTICE_PATH.md` | 2 |
| `CLAUDE.md` | 2 |

`docs/SCRIPTING_GUIDELINES.md` 는 참조 갱신에 더해 신규 스크립트 템플릿·`add_apt_repo` 사용법 절이 새 파일 구조를 가리키도록 고친다.

## 6. 주석 기준

**형식**
- 블록당 **What 1줄 + 필요하면 Why 1줄**.
- Google-style `Globals: / Arguments: / Outputs: / Returns:` 배너는 전면 제거하고 함수 위 1줄로 대체한다. 인자는 함수 첫 줄의 `local a="$1" b="$2"` 가 이미 보여준다.
- 저작권 배너 4줄은 파일마다 유지한다 (18파일 72줄 → 6파일 24줄).

**독자 수준**: 전공 지식은 있으나 ROS2·DDS 도메인은 처음인 대학 3~4학년.
- 도메인 용어(RMW, DDS discovery, HWE 커널, DKMS, colcon overlay)는 **첫 등장 시 한 번만** 짧게 부연한다.
- bash 관용구(`set -euo pipefail`, `:=`, `${VAR:?}`)는 설명하지 않는다 — 찾아볼 수 있다.

**제거 대상**
- 결정 날짜, ADR 번호, 내부 단계 코드, 룰 번호 인용 (`"사용자 결정 2026-05-28"`, `"ADR-027"`, `"Hard Rule #4"`).
- 폐기된 구조의 이력 서술 (`"구 run_stage_a02 였고 …로 옮김"`, `"voice_container wrapper 폐기"`).
- 같은 사실의 반복 — 예: `config.sh` 의 `CYCLONEDDS_XML` 설명은 3문단이 같은 내용을 각도만 바꿔 말한다.

**`docs/...` 포인터를 넣지 않는다**: `docs/` 는 main 트리에 없다(§3). 링크를 걸면 공개 브랜치에서 죽은 참조가 된다. 근거는 한 줄로 직접 서술한다.

**예시** — `config.sh` NVIDIA 블록 (13줄 → 4줄)

```bash
# NVIDIA 드라이버 버전 핀. 자동 선택(ubuntu-drivers)은 머신마다 다른 걸 골라 재부팅 후
# 검은 화면이 난 적 있어 검증된 버전으로 고정한다.
# FLAVOR: "" = closed(기본), "-open" = open 커널 모듈.
: "${NVIDIA_DRIVER_VERSION:=595}"
: "${NVIDIA_DRIVER_FLAVOR:=}"
```

## 7. 검증

순수 리팩토링이므로 "동작이 같다"를 증명해야 한다. before = 승격 직후의 `main`, after = `refactor/resources-merge`.

### 7.1 정적 (로컬, sudo 불필요)

```bash
shellcheck resources/*.sh install.sh setup-app.sh
bash -n resources/*.sh install.sh setup-app.sh
```

`shellcheck` 0.8.0 이 로컬(192.168.1.2)에 있다. 원격(192.168.1.11)에는 없다.

### 7.2 계약 스냅샷 diff (로컬, sudo 불필요)

`git worktree add` 로 `main` 을 따로 펼쳐 두고 두 트리에서 각각 실행해 비교한다.

```bash
bash -c 'set -a; source resources/config.sh; declare -px' | sort   # 환경변수 집합
bash -c 'source resources/config.sh; source resources/lib.sh; declare -F' | sort   # 함수 집합
```

환경변수 집합은 **완전 일치**해야 한다. 함수 집합의 허용 차이는 두 가지뿐이다 — `step_end_ok/fail/skip` 3개가 `step_end` 1개로 통합된 것, 그리고 진입점에 중복 정의돼 있던 `print_copyright` 가 `lib.sh` 로 들어온 것. 그 외 이름이 늘거나 줄면 실수다.

### 7.3 명령 트레이스 diff (로컬, sudo 불필요)

`scripts/trace-steps.sh` 를 dev 브랜치에 새로 만든다(main 트리에 `scripts/` 가 없다). `PATH` 앞에 스텁 디렉토리를 놓고 `sudo` `apt-get` `curl` `wget` `gpg` `tee` `nmcli` `rosdep` `colcon` `docker` 를 `echo "$0 $*"` 로 대체한 뒤, 각 설치 본문을 실행해 **실행됐을 명령 목록**을 파일로 남긴다. before/after 트레이스가 같아야 한다.

스텁은 파일을 만들지 않으므로 반복 실행해도 결과가 변하지 않는다. 이것이 "명령·순서·조건 분기를 바꾸지 않았다"의 직접 증거다.

### 7.4 실기 스모크 (192.168.1.11, `ssh -t` 로 sudo 비번 1회)

대상 머신은 `rokey-test`, ROS2 jazzy · Docker 29.6.2 · NVIDIA 595.84 · `cobot2_ws` 빌드 완료 상태이고 `main` 브랜치를 체크아웃해 두었다. `~/.ros2_jazzy_test/state` 가 없으므로 `install.sh` 전체 실행은 step 1부터 돌면서 step 6 에서 재부팅을 요구한다 — 그래서 전체 실행은 하지 않고 아래만 돌린다. 모두 멱등이고 수 분이면 끝난다.

```bash
git -C ~/ros2_jazzy_test fetch origin refactor/resources-merge
git -C ~/ros2_jazzy_test checkout refactor/resources-merge

bash install.sh --status
bash install.sh --help
source resources/activate.sh && ros2 pkg list | head
bash resources/base-install.sh kernel     # apt no-op
bash resources/base-install.sh vscode     # apt no-op
bash resources/hostcfg.sh dds             # XML 재렌더 → 기존 파일과 diff 0 이어야 정상
```

스모크가 끝나면 `main` 으로 되돌려 그 머신을 공개 설치 검증 상태로 남긴다.

`hostcfg.sh network` 는 돌리지 않는다. SSH 는 무선(`wlo1`, 192.168.1.11)이고 대상은 유선(`enp4s0`, DOWN)이라 연결이 끊기지는 않지만, 머신 설정을 바꾸는 단계라 스모크에 넣을 이유가 없다.

## 8. 커밋 분할

한 논리 변경 단위로 나눈다. 각 커밋 후 §7.1 정적 검사를 통과해야 한다.

`refactor/resources-merge` (base `main`)

1. 라이브러리 3개를 `lib.sh` 로 병합
2. base 설치 5개를 `base-install.sh` 로 병합
3. app 설치 5개를 `app-install.sh` 로 병합
4. host 설정 2개를 `hostcfg.sh` 로 병합
5. 재개 런처를 `install.sh --resume-terminal` 로 흡수
6. `setup-app.sh` 가 공용 단계 러너를 쓰도록 교체
7. 주석 정리 (`resources/` + 진입점 2개)
8. `README.md` 전환 안내 삭제 + `containers/` 참조 갱신

`fix/dsr-clone-pin` (dev)

9. 이 spec + `scripts/trace-steps.sh`
10. `docs/*` · `CLAUDE.md` 파일명 참조 갱신 (리팩토링이 main 에 머지된 뒤)

커밋 메시지는 한국어로 쓰고 내부 축약어(단계 번호·결정 번호·룰 번호)를 쓰지 않는다.

## 9. 리스크

| 리스크 | 대응 |
|---|---|
| state 키가 바뀌면 설치 진행 중인 머신이 완료 단계를 다시 돈다 | §4.1 표의 키를 그대로 유지. §7.2 스냅샷과 `install.sh --status` 로 확인 |
| 재개 autostart 는 GUI 로그인이 있어야 검증된다 | `Exec` 인용 구조를 현재와 동일하게 유지(§5.4). 실기 검증 불가를 명시하고 남긴다 |
| `setup-app.sh` 가 `run_step` 을 쓰면서 재개 동작이 새로 생길 수 있다 | `STEP_STATE=0` 으로 state 기록을 끈다. `~/.ros2_jazzy_test/state` 에 setup-app 키가 생기지 않는지 확인 |
| 주석을 지우면서 근거가 사라진다 | 근거는 `docs/` 4개 문서에 이미 있다. 한 줄 Why 는 남긴다 |
| 문서 참조 치환 누락 | 양쪽 브랜치에서 `grep -rnE "resources/[a-z0-9-]+\.sh"` 로 남은 옛 파일명 확인. 불변 기록(§2 비포함)은 제외 |
| 두 브랜치로 나뉘어 문서가 코드보다 먼저 머지되면 죽은 참조가 생긴다 | §3 통합 순서를 지킨다 — 코드가 main 에 들어간 뒤 dev 가 `git merge main` 하고, 그다음 문서 참조를 고친다 |
| main 승격을 건너뛰면 옛 `dsr-project-install.sh` 를 흡수하게 된다 | §3.1 선행 조건을 먼저 수행한다 |

## 10. 예상 결과

| | before (`main`) | after (추정) |
|---|---|---|
| `resources/*.sh` | 18파일 2063줄 | 6파일 ~900줄 |
| `setup-app.sh` | 316줄 | ~180줄 |
| `install.sh` | 222줄 | ~150줄 |
| 합계 | 2601줄 | ~1230줄 (−53%) |
