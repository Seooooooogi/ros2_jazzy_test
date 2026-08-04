# resources/ 셸 스크립트 병합 + 주석 다이어트 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `resources/` 의 셸 스크립트 18개를 역할별 6개로 합치고 주석을 "무엇 한 줄 + 왜 한 줄" 수준으로 줄여, 설치 동작을 하나도 바꾸지 않은 채 전체 코드량을 절반으로 낮춘다.

**Architecture:** 설치 본문 13개를 `base-install.sh` / `app-install.sh` / `hostcfg.sh` 세 개의 서브커맨드 스크립트로 흡수하고, 라이브러리 3개(`orchestrate` `interaction` `apt-repo`)를 `lib.sh` 하나로 합친다. `config.sh` 와 `activate.sh` 는 외부 계약이라 경로·변수명을 유지한다. 동작 동일성은 명령 트레이스 스텁 하네스로 리팩토링 전 baseline 과 비교해 증명한다.

**Tech Stack:** bash 5.2 (Ubuntu 24.04 noble), shellcheck 0.8.0, git worktree

## Global Constraints

- **동작 변경 금지.** 명령·순서·조건 분기를 바꾸지 않는다. 기능 추가도 하지 않는다.
- **state 키 보존.** `a01_kernel_baseline` `a01_nvidia_driver` `a01_docker` `a01_ros2_desktop` `a01_ros2_extras` `a01_reboot` `a03_vscode` `dds_tuning` `network_static_ip` — `run_step` 의 두 번째 인자를 바꾸면 설치 진행 중인 머신이 완료 단계를 다시 돈다.
- **공개 API 불변.** `resources/config.sh` 와 `resources/activate.sh` 는 경로도 변수명도 바꾸지 않는다. `~/.bashrc`·docker compose·`containers/bringup.sh:39` 가 직접 source 한다.
- **`set -euo pipefail` 은 실행 진입점에만.** source 전용 라이브러리(`config.sh` `lib.sh` `activate.sh`)에는 두지 않는다 — 호출자 셸 옵션을 오염시킨다.
- **비-셸 자산 경로 고정.** `resources/cyclonedds.xml.in` · `resources/sysctl-cyclonedds.conf` · `resources/oww_models/` 는 이름도 위치도 바꾸지 않는다. `scripts/venv-demo/LAB.md:112` 와 `scripts/venv-demo/uv/setup.sh:65` 가 `oww_models/` 를 절대 경로로 참조한다.
- **주석 형식.** 블록당 What 한 줄 + 필요하면 Why 한 줄. Google-style `Globals:/Arguments:/Outputs:/Returns:` 배너 전면 금지. 저작권 배너 4줄은 파일마다 유지.
- **주석에 `docs/...` 링크 금지.** `docs/` 는 `main` 트리에 없어 공개 브랜치에서 죽은 참조가 된다.
- **주석에 결정 날짜·ADR 번호·단계 코드·룰 번호 금지.** (`"사용자 결정 2026-05-28"`, `"ADR-027"`, `"Hard Rule #4"`, `"구 run_stage_a02"`)
- **커밋 메시지는 한국어, AI attribution 금지.** `Co-Authored-By` / `Generated with` 류를 넣지 않는다.
- **브랜치 분리.** 코드는 `refactor/resources-merge`(base `main`), 문서·검증 하네스는 `fix/dsr-clone-pin`. `README.md` 는 `.main-keep-ours` 라 main 기준 브랜치에서만 고쳐야 실제로 반영된다.

## Setup — 두 브랜치 동시 작업

**선행 조건은 이미 끝나 있다**: `fix/dsr-clone-pin` 의 미승격 4커밋을 `main` 으로 승격하고 push 했다(`65489ac`). `refactor/resources-merge` 의 base 인 `main` 에 doosan-robot2 커밋 핀과 새 `dsr-project-install.sh` 가 들어 있다. `git log --oneline -1 main` 이 `65489ac` 이상인지 확인하고 시작한다.

`docs/` 와 `scripts/` 는 `main` 트리에 없다. 계획서와 검증 하네스를 보면서 코드를 고치려면 worktree 두 개가 필요하다.

```bash
cd ~/ros2_jazzy_test                                    # fix/dsr-clone-pin — 계획서 + 하네스
git worktree add ../rjt-refactor refactor/resources-merge   # 코드 작업 디렉토리
```

이후 **코드 편집은 `~/rjt-refactor`**, **하네스 실행과 문서 편집은 `~/ros2_jazzy_test`** 에서 한다.

## 파일 구조

`~/rjt-refactor/resources/` 최종 형태:

| 파일 | 책임 | 실행 방식 |
|---|---|---|
| `config.sh` | 버전 핀·경로 정의만. 함수는 `config_assert_set` 하나 | source 전용 |
| `activate.sh` | ROS2 + 워크스페이스 overlay 활성화 | source 전용 |
| `lib.sh` | 단계 엔진(state·run_step) + 사용자 상호작용 + apt repo 등록 | source 전용 |
| `base-install.sh` | reboot 이전/직후의 시스템 계층 설치 6종 | `bash base-install.sh <sub>` |
| `app-install.sh` | 워크스페이스·앱 계층 설치 6종 | `bash app-install.sh <sub>` |
| `hostcfg.sh` | 설치 후 호스트 런타임 설정 2종 | `bash hostcfg.sh <sub>` |

`cyclonedds.xml.in` · `sysctl-cyclonedds.conf` · `oww_models/` 는 그대로 남는다.

---

### Task 1: 명령 트레이스 하네스 + baseline 캡처

리팩토링을 시작하기 전에 "지금 무슨 명령이 실행되는가"를 파일로 굳혀 둔다. 이후 모든 태스크는 이 baseline 과 비교해 검증한다.

**Files:**
- Create: `~/ros2_jazzy_test/scripts/trace-steps.sh` (dev 브랜치)
- Create: `~/ros2_jazzy_test/.trace-baseline/` (git-ignore 대상, 커밋하지 않음)

**Interfaces:**
- Produces: `bash scripts/trace-steps.sh <repo-dir> <out-dir>` — `<out-dir>/<step>.trace` 파일들을 만든다. 각 파일은 그 단계가 실행했을 명령 목록 + 스크립트 자체 출력 + 마지막 줄 `exit=<rc>`.

- [ ] **Step 1: 하네스 작성**

`~/ros2_jazzy_test/scripts/trace-steps.sh`:

```bash
#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# scripts/trace-steps.sh — 설치 본문이 "실행했을 명령"을 스텁으로 가로채 파일로 남긴다.
# 리팩토링 전후 트레이스가 같으면 명령·순서·조건 분기를 안 건드렸다는 뜻이다.
#
# 사용법: bash scripts/trace-steps.sh <repo-dir> <out-dir>
#   예:   bash scripts/trace-steps.sh ~/ros2_jazzy_test .trace-baseline
#         bash scripts/trace-steps.sh ~/rjt-refactor   .trace-after
#         diff -ru .trace-baseline .trace-after
#
# set -e 를 켜지 않는다 — 스텁 환경에서 본문이 중간에 실패하는 것은 정상이고,
# 실패 지점이 전후로 같은지가 곧 검증 대상이다.
set -uo pipefail

REPO="$(cd "${1:?usage: trace-steps.sh <repo-dir> <out-dir>}" && pwd)"
OUT="${2:?usage: trace-steps.sh <repo-dir> <out-dir>}"
mkdir -p "${OUT}"

# 스텁·가짜 홈은 고정 경로를 쓴다. mktemp -d 로 만들면 실행마다 경로가 달라져
# 트레이스에 그 경로가 섞이고, 전후 비교가 전부 다르다고 나온다.
STUB=/tmp/trace-steps-stub
FAKEHOME=/tmp/trace-steps-home
rm -rf "${STUB}" "${FAKEHOME}"
mkdir -p "${STUB}" "${FAKEHOME}/cobot2_ws/src" "${FAKEHOME}/.config"
touch "${FAKEHOME}/.bashrc"

# 시스템을 바꾸는 명령을 전부 echo 로 갈아끼운다. 실제 실행이 없으니 몇 번을 돌려도 상태가 안 변한다.
for c in sudo apt-get apt-key add-apt-repository curl wget gpg nmcli rosdep colcon docker \
         systemctl usermod modprobe dkms update-initramfs pip pip3 snap tee; do
    printf '#!/usr/bin/env bash\necho "CMD %s $*"\n' "${c}" > "${STUB}/${c}"
    chmod +x "${STUB}/${c}"
done

# 병합 후 레이아웃인지 병합 전 레이아웃인지는 새 파일 존재로 판별한다.
if [[ -f "${REPO}/resources/base-install.sh" ]]; then
    STEPS=(
        "kernel|base-install.sh kernel"
        "nvidia|base-install.sh nvidia"
        "docker|base-install.sh docker"
        "ros2_desktop|base-install.sh ros2-desktop"
        "ros2_extras|base-install.sh ros2-extras"
        "vscode|base-install.sh vscode"
        "dds|hostcfg.sh dds"
        "network|hostcfg.sh network"
        "dsr|app-install.sh dsr"
        "realsense_sdk|app-install.sh realsense-sdk"
        "realsense_ros|app-install.sh realsense-ros"
        "voice|app-install.sh voice"
        "colcon|app-install.sh colcon"
        "toolkit|app-install.sh toolkit"
    )
else
    STEPS=(
        "kernel|kernel-baseline.sh"
        "nvidia|nvidia-driver-install.sh"
        "docker|docker-install.sh"
        "ros2_desktop|ros2-packages.sh desktop"
        "ros2_extras|ros2-packages.sh extras"
        "vscode|vscode-install.sh"
        "dds|dds-tuning.sh"
        "network|network-static-ip.sh"
        "dsr|dsr-project-install.sh"
        "realsense_sdk|realsense-install.sh sdk"
        "realsense_ros|realsense-install.sh ros"
        "voice|voice-host-install.sh"
        "colcon|colcon-build.sh"
        "toolkit|nvidia-container-toolkit-install.sh"
    )
fi

for entry in "${STEPS[@]}"; do
    name="${entry%%|*}"
    cmd="${entry#*|}"
    rc=0
    # 레포 경로는 트레이스에 그대로 찍히므로 <REPO> 로 치환한다 — 두 worktree 경로가 다르기 때문.
    # shellcheck disable=SC2086
    ( cd "${REPO}" && PATH="${STUB}:${PATH}" HOME="${FAKEHOME}" \
        ASSUME_YES=1 SKIP_IF_NO_GPU=1 bash resources/${cmd} ) > "${OUT}/${name}.raw" 2>&1 || rc=$?
    sed -e "s#${REPO}#<REPO>#g" -e "s#${FAKEHOME}#<HOME>#g" -e "s#${STUB}#<STUB>#g" \
        "${OUT}/${name}.raw" > "${OUT}/${name}.trace"
    echo "exit=${rc}" >> "${OUT}/${name}.trace"
    rm -f "${OUT}/${name}.raw"
    echo "  traced ${name} (exit=${rc})"
done

echo "trace-steps: wrote $(ls -1 "${OUT}"/*.trace | wc -l) traces to ${OUT}"
```

- [ ] **Step 2: 하네스 정적 검사**

```bash
cd ~/ros2_jazzy_test
shellcheck scripts/trace-steps.sh && bash -n scripts/trace-steps.sh
```

Expected: 출력 없음(통과).

- [ ] **Step 3: baseline 캡처 — 리팩토링 전 코드에서**

`main` 을 별도 worktree 로 펼쳐서 캡처한다. `~/ros2_jazzy_test`(dev)는 `main` 과 `resources/` 내용이 같지만, 기준을 명시적으로 `main` 에 고정한다.

```bash
cd ~/ros2_jazzy_test
git worktree add ../rjt-main main
bash scripts/trace-steps.sh ~/rjt-main .trace-baseline
```

Expected: `traced kernel (exit=...)` 부터 `traced toolkit` 까지 14줄 + `wrote 14 traces`.

- [ ] **Step 4: baseline 이 결정적인지 확인 — 두 번 돌려 같은지 본다**

```bash
cd ~/ros2_jazzy_test
bash scripts/trace-steps.sh ~/rjt-main .trace-recheck
diff -ru .trace-baseline .trace-recheck && echo "DETERMINISTIC"
```

Expected: `DETERMINISTIC`.

차이가 나면 그 파일에 시각·난수·임시 경로가 섞인 것이다. 하네스의 `sed` 치환 목록에 그 값을 추가하고 Step 3 부터 다시 한다. 하네스가 결정적이지 않으면 이후 모든 검증이 무의미하므로 **여기서 반드시 통과시킨다**.

```bash
rm -rf .trace-recheck
```

- [ ] **Step 5: 트레이스 산출물을 git 에서 제외**

`~/ros2_jazzy_test/.gitignore` 끝에 추가:

```
# 리팩토링 동작 동일성 비교용 명령 트레이스 — 머신에서 재생성 가능
.trace-baseline/
.trace-after/
```

- [ ] **Step 6: 커밋 (dev 브랜치)**

```bash
cd ~/ros2_jazzy_test
git add scripts/trace-steps.sh .gitignore
git commit -m "설치 본문이 실행할 명령을 기록해 비교하는 검증 스크립트 추가

시스템을 바꾸는 명령을 전부 스텁으로 갈아끼워 실제 실행 없이 명령 목록만
파일로 남긴다. 스크립트를 합치기 전후의 목록이 같으면 동작이 안 바뀐 것."
```

---

### Task 2: `lib.sh` — 라이브러리 3개 병합

**Files:**
- Create: `~/rjt-refactor/resources/lib.sh`
- Delete: `~/rjt-refactor/resources/orchestrate.sh`, `resources/interaction.sh`, `resources/apt-repo.sh`
- Modify: `~/rjt-refactor/install.sh:43-46`, `setup-app.sh` 의 source 줄
- Modify: `~/rjt-refactor/resources/{docker-install,vscode-install,ros2-packages,realsense-install,nvidia-container-toolkit-install}.sh` 의 source 줄

**Interfaces:**
- Produces: `lib.sh` 가 정의하는 이름 — `step_should_skip` `step_begin` `step_end` `state_dump` `run_step` `run_step_skip` `install_steps_total` `run_stage_a01` `run_stage_a03` `add_apt_repo` `confirm_or_abort` `confirm_or_abort_assumable` `register_resume_autostart` `remove_resume_autostart` `sudo_prime` `print_copyright`, 변수 `STEP_STATE`(기본 1) `STAGE_A01_COUNT` `STAGE_A03_COUNT` `INSTALL_EXTRA_COUNT` `RESUME_AUTOSTART_DIR` `RESUME_AUTOSTART_FILE`.
- Consumes: `config.sh` 의 `STATE_FILE` `LOG_FILE` `STATE_DIR` `TOTAL_STEPS` `KEYRING_DIR`.

- [ ] **Step 1: 세 파일을 한 파일로 이어붙인다**

```bash
cd ~/rjt-refactor
git mv resources/orchestrate.sh resources/lib.sh
{ echo; cat resources/interaction.sh; echo; cat resources/apt-repo.sh; } >> resources/lib.sh
git rm -q resources/interaction.sh resources/apt-repo.sh
```

이어붙인 파일에서 아래를 손으로 정리한다. **함수 본문은 건드리지 않는다.**
- 중간에 두 번 더 들어온 shebang(`#!/usr/bin/env bash`)과 저작권 배너 4줄을 지운다. 파일 맨 위 것만 남긴다.
- 파일 헤더 주석을 한 덩어리로 합친다(§주석 기준은 Task 8 에서 일괄 적용하므로 여기서는 구조만).

- [ ] **Step 2: `step_end_ok` / `step_end_fail` / `step_end_skip` 을 하나로 합친다**

세 함수를 지우고 그 자리에 넣는다:

```bash
# 현재 단계를 마무리하고 state 에 결과를 남긴다. status = DONE | FAIL | SKIPPED.
step_end() {
    local status="${1:-DONE}"
    if [[ -z "${__current_step}" ]]; then
        echo "state: step_end called without step_begin" >&2
        return 1
    fi
    _state_set "${__current_step}" "${status}"
    case "${status}" in
        DONE)    echo "[OK]  step ${__current_step} = DONE" ;;
        FAIL)    echo "[FAIL] step ${__current_step} = FAIL" >&2 ;;
        SKIPPED) echo "[SKIP] step ${__current_step} = SKIPPED" ;;
    esac
    __current_step=""
}
```

호출부를 바꾼다:
- `lib.sh` 안 `run_step` 의 `step_end_ok` → `step_end DONE`, `step_end_fail` → `step_end FAIL`
- `install.sh:183` 의 `step_end_ok` → `step_end DONE`

`step_end_skip` 은 원래 어디서도 호출되지 않으므로 호출부 변경이 없다.

- [ ] **Step 3: `STEP_STATE` 가드를 넣는다**

`lib.sh` 상단(`__current_step=""` 옆)에 추가:

```bash
# 1 = 단계 결과를 state 파일에 남기고 완료된 단계는 건너뛴다(install.sh — 재부팅을 넘어 재개해야 함).
# 0 = 배너·로그·heartbeat 만 하고 state 는 안 건드린다(setup-app.sh — 재개 개념이 없다).
: "${STEP_STATE:=1}"
```

`run_step` 의 skip 판정과 begin/end 를 가드로 감싼다:

```bash
    if [[ "${STEP_STATE}" == 1 ]] && step_should_skip "${name}"; then
        echo "[${n}/${total}] skip: ${name} (already $(_state_get "${name}" | tr '[:upper:]' '[:lower:]'))"
        return 0
    fi
```

`step_begin` 안의 `_state_set "$name" RUNNING` 과 `step_end` 안의 `_state_set` 을 각각 감싼다:

```bash
    [[ "${STEP_STATE}" == 1 ]] && _state_set "${name}" RUNNING
```

```bash
    [[ "${STEP_STATE}" == 1 ]] && _state_set "${__current_step}" "${status}"
```

`run_step_skip` 의 `step_should_skip` 판정과 `_state_set` 도 같은 방식으로 감싼다.

주의: `[[ ... ]] && cmd` 는 조건이 거짓이면 반환값이 1이다. `set -e` 아래 함수 마지막 줄이면 함수가 실패로 끝난다. 위 세 자리는 모두 뒤에 다른 문장이 이어지므로 안전하지만, 함수 끝에 놓게 되면 `|| true` 를 붙인다.

- [ ] **Step 4: `print_copyright` 을 `lib.sh` 로 옮긴다**

`install.sh:83-90` 의 함수 정의를 **한 글자도 바꾸지 않고** 잘라내 `lib.sh` 끝에 붙인다. 위의 주석 한 줄만 새로 얹는다:

```bash
# 설치 실행마다 콘솔에 찍는 저작권 배너. 재부팅 후 자동 재개된 터미널에서도 나온다.
print_copyright() {
    cat <<'EOF'
============================================================
 Cobot2 Jazzy Installer
 Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
============================================================
EOF
}
```

`setup-app.sh:66-73` 의 `print_copyright()` 정의도 지운다. 두 정의는 내용이 같으므로 어느 쪽을 남겨도 출력이 같다.

- [ ] **Step 5: source 줄을 전부 `lib.sh` 로 바꾼다**

```bash
cd ~/rjt-refactor
sed -i 's#/orchestrate\.sh"#/lib.sh"#; s#source=resources/orchestrate\.sh#source=resources/lib.sh#' install.sh
grep -rln 'interaction\.sh\|apt-repo\.sh' install.sh setup-app.sh resources/
```

`install.sh` 는 `config.sh` → `orchestrate.sh` → `interaction.sh` 세 줄을 source 하고 있다. 두 줄로 줄인다:

```bash
# shellcheck source=resources/config.sh
source "${RESOURCE_DIR}/config.sh"
# shellcheck source=resources/lib.sh
source "${RESOURCE_DIR}/lib.sh"
config_assert_set
```

`setup-app.sh` 의 `source "${RESOURCE_DIR}/interaction.sh"` 도 `lib.sh` 로 바꾼다.

아래 5개 설치 본문은 `apt-repo.sh`(일부는 `interaction.sh` 도) 를 source 하고 있다. 각각 `lib.sh` 한 줄로 바꾼다 — `lib.sh` 는 source 시점에 부작용이 없으므로 함께 딸려 오는 단계 엔진은 무해하다.

| 파일 | 현재 source | 바꿀 것 |
|---|---|---|
| `resources/docker-install.sh:21` | `apt-repo.sh` | `lib.sh` |
| `resources/vscode-install.sh:21` | `apt-repo.sh` | `lib.sh` |
| `resources/ros2-packages.sh:28` | `apt-repo.sh` | `lib.sh` |
| `resources/realsense-install.sh:23` | `apt-repo.sh` | `lib.sh` |
| `resources/nvidia-container-toolkit-install.sh:27,29` | `interaction.sh` + `apt-repo.sh` (두 줄) | `lib.sh` 한 줄 |

- [ ] **Step 6: 정적 검사**

```bash
cd ~/rjt-refactor
shellcheck resources/*.sh install.sh setup-app.sh
bash -n resources/*.sh install.sh setup-app.sh
```

Expected: 출력 없음.

- [ ] **Step 7: 함수·변수 계약 비교**

```bash
cd ~/ros2_jazzy_test
diff <(bash -c 'set -a; source ~/rjt-main/resources/config.sh; declare -px' | sort) \
     <(bash -c 'set -a; source ~/rjt-refactor/resources/config.sh; declare -px' | sort)
```

Expected: 차이 없음(`config.sh` 는 아직 안 건드렸다).

```bash
diff <(bash -c 'source ~/rjt-main/resources/config.sh; source ~/rjt-main/resources/orchestrate.sh; source ~/rjt-main/resources/interaction.sh; source ~/rjt-main/resources/apt-repo.sh; declare -F' | awk '{print $3}' | sort) \
     <(bash -c 'source ~/rjt-refactor/resources/config.sh; source ~/rjt-refactor/resources/lib.sh; declare -F' | awk '{print $3}' | sort)
```

Expected: 정확히 아래 차이만.

```
< step_end_fail
< step_end_ok
< step_end_skip
> print_copyright
> step_end
```

다른 이름이 늘거나 줄면 실수다.

- [ ] **Step 8: 트레이스 비교**

```bash
cd ~/ros2_jazzy_test
rm -rf .trace-after && bash scripts/trace-steps.sh ~/rjt-refactor .trace-after
diff -ru .trace-baseline .trace-after && echo "TRACE IDENTICAL"
```

Expected: `TRACE IDENTICAL`. 이 태스크는 설치 본문 로직을 안 건드렸으므로 트레이스가 완전히 같아야 한다.

- [ ] **Step 9: `install.sh --status` / `--help` 가 도는지**

```bash
cd ~/rjt-refactor && bash install.sh --help >/dev/null && bash install.sh --status && echo "ENTRYPOINT OK"
```

Expected: state 덤프 출력 후 `ENTRYPOINT OK`.

- [ ] **Step 10: 커밋**

```bash
cd ~/rjt-refactor
git add -A
git commit -m "설치 라이브러리 세 개를 한 파일로 합침

단계 엔진 / 사용자 확인 / apt 저장소 등록은 늘 함께 불려 다녀서 파일을
나눠 둘 이유가 없었다. 합치면서 종료 처리 함수 세 개를 상태 인자를 받는
하나로 줄이고, 저작권 배너 출력 함수의 중복 정의도 한 곳으로 모았다.

단계 상태 기록은 STEP_STATE 로 켜고 끌 수 있게 했다 — 재부팅을 넘어
이어서 진행해야 하는 쪽만 기록이 필요하다."
```

---

### Task 3: `base-install.sh` — 시스템 계층 5개 병합

**Files:**
- Create: `~/rjt-refactor/resources/base-install.sh`
- Delete: `resources/kernel-baseline.sh`, `nvidia-driver-install.sh`, `docker-install.sh`, `ros2-packages.sh`, `vscode-install.sh`
- Modify: `~/rjt-refactor/resources/lib.sh` 의 `run_stage_a01` / `run_stage_a03`

**Interfaces:**
- Produces: `bash resources/base-install.sh <kernel|nvidia|docker|ros2-desktop|ros2-extras|vscode>`
- Consumes: Task 2 의 `lib.sh` (`add_apt_repo`).

- [ ] **Step 1: 새 파일 뼈대를 만든다**

`~/rjt-refactor/resources/base-install.sh`:

```bash
#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/base-install.sh — 재부팅 앞뒤로 도는 시스템 계층 설치.
# 서브커맨드마다 별도 프로세스로 실행되므로 한쪽이 실패해도 다른 쪽에 영향이 없다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
config_assert_set

# ... 함수 정의 — 다음 Step 의 표대로 원본 본문을 그대로 옮겨 온다 ...

case "${1:?base-install: subcommand required (kernel|nvidia|docker|ros2-desktop|ros2-extras|vscode)}" in
    kernel)       base_kernel ;;
    nvidia)       base_nvidia ;;
    docker)       base_docker ;;
    ros2-desktop) ros2_desktop ;;
    ros2-extras)  ros2_extras ;;
    vscode)       base_vscode ;;
    *) echo "base-install: unknown subcommand '$1'" >&2; exit 2 ;;
esac
```

- [ ] **Step 2: 다섯 스크립트의 본문을 함수로 옮긴다**

각 원본에서 **shebang·저작권 배너·`set -euo pipefail`·`SCRIPT_DIR=`·`source`·`config_assert_set` 을 뺀 나머지 전부**를 함수 본문으로 옮긴다.

| 원본 | 함수명 | 파일 최상단 상수 처리 |
|---|---|---|
| `kernel-baseline.sh` | `base_kernel()` | 없음. `running=` 을 `local running` 으로 |
| `nvidia-driver-install.sh` | `base_nvidia()` | 기존 `_resolve_driver_pkg()` 는 그대로 별도 함수로 둔다 |
| `docker-install.sh` | `base_docker()` | `DOCKER_LIST` `DOCKER_KEY` 를 함수 안 `local` 로 |
| `ros2-packages.sh` | `ros2_desktop()` `ros2_extras()` | 이미 함수다. 그대로 옮기고 원본 끝의 `case` 는 버린다 |
| `vscode-install.sh` | `base_vscode()` | `MS_KEY` `VSCODE_LIST` `arch` 를 함수 안 `local` 로 |

**최상단 상수를 반드시 `local` 로 내려야 한다.** 한 파일에 모이면 전역 이름이 겹치고, `set -u` 아래에서 다른 서브커맨드가 남의 변수를 보게 된다.

`ros2_desktop` / `ros2_extras` 는 이름을 바꾸지 않는다 — 이미 그 이름이고 트레이스 비교가 쉬워진다.

- [ ] **Step 3: 원본 5개를 지운다**

```bash
cd ~/rjt-refactor
git rm -q resources/kernel-baseline.sh resources/nvidia-driver-install.sh \
          resources/docker-install.sh resources/ros2-packages.sh resources/vscode-install.sh
git add resources/base-install.sh
```

- [ ] **Step 4: `lib.sh` 의 스테이지 함수가 새 파일을 부르게 한다**

`run_stage_a01`:

```bash
run_stage_a01() {
    local off="$1" skip_nvidia="${2:-0}"
    run_step $((off + 1)) a01_kernel_baseline bash "${RESOURCE_DIR}/base-install.sh" kernel
    if [[ "$skip_nvidia" == 1 ]]; then
        run_step_skip $((off + 2)) a01_nvidia_driver "nvidia driver assumed pre-installed (--no-nvidia-driver)"
    else
        run_step $((off + 2)) a01_nvidia_driver bash "${RESOURCE_DIR}/base-install.sh" nvidia
    fi
    run_step $((off + 3)) a01_docker       bash "${RESOURCE_DIR}/base-install.sh" docker
    run_step $((off + 4)) a01_ros2_desktop bash "${RESOURCE_DIR}/base-install.sh" ros2-desktop
    run_step $((off + 5)) a01_ros2_extras  bash "${RESOURCE_DIR}/base-install.sh" ros2-extras
}
```

`run_stage_a03`:

```bash
run_stage_a03() {
    local off="$1"
    run_step $((off + 1)) a03_vscode bash "${RESOURCE_DIR}/base-install.sh" vscode
}
```

**state 키 6개가 그대로인지 눈으로 확인한다.**

- [ ] **Step 5: 정적 검사**

```bash
cd ~/rjt-refactor && shellcheck resources/*.sh install.sh setup-app.sh && bash -n resources/*.sh
```

Expected: 출력 없음.

- [ ] **Step 6: 트레이스 비교**

```bash
cd ~/ros2_jazzy_test
rm -rf .trace-after && bash scripts/trace-steps.sh ~/rjt-refactor .trace-after
diff -ru .trace-baseline .trace-after && echo "TRACE IDENTICAL"
```

Expected: `TRACE IDENTICAL`.

차이가 나면 대개 원인이 셋 중 하나다 — 최상단 상수를 `local` 로 안 내려서 값이 비었거나, 본문 일부를 빠뜨렸거나, `exit 1` 이 함수 안에서 `return` 으로 바뀌었거나. **`exit` 을 `return` 으로 바꾸지 않는다** — 서브커맨드는 별도 프로세스라 `exit` 이 그대로 맞다.

- [ ] **Step 7: 커밋**

```bash
cd ~/rjt-refactor
git add -A
git commit -m "재부팅 앞뒤의 시스템 설치 다섯 개를 한 파일로 합침

커널 기준선 / 그래픽 드라이버 / 도커 / ROS2 두 묶음 / 편집기 설치는
모두 같은 성격이라 파일마다 헤더와 설정 읽기를 반복할 이유가 없었다.
서브커맨드로 부르는 방식은 ROS2 설치가 원래 쓰던 것을 그대로 넓힌 것이다.

재개에 쓰는 단계 이름은 하나도 바꾸지 않아, 설치를 진행 중인 머신도
끊긴 지점부터 그대로 이어진다."
```

---

### Task 4: `app-install.sh` — 앱 계층 5개 병합

**Files:**
- Create: `~/rjt-refactor/resources/app-install.sh`
- Delete: `resources/dsr-project-install.sh`, `realsense-install.sh`, `voice-host-install.sh`, `colcon-build.sh`, `nvidia-container-toolkit-install.sh`
- Modify: `~/rjt-refactor/setup-app.sh` 의 `do_workspace` / `do_containers`

**Interfaces:**
- Produces: `bash resources/app-install.sh <dsr|realsense-sdk|realsense-ros|voice|colcon|toolkit>`

- [ ] **Step 1: 새 파일 뼈대**

```bash
#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/app-install.sh — 워크스페이스와 앱 계층 설치. base 설치가 끝난 뒤 setup-app.sh 가 부른다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
config_assert_set

# ... 함수 정의 — 다음 Step 의 표대로 원본 본문을 그대로 옮겨 온다 ...

case "${1:?app-install: subcommand required (dsr|realsense-sdk|realsense-ros|voice|colcon|toolkit)}" in
    dsr)           app_dsr ;;
    realsense-sdk) realsense_sdk ;;
    realsense-ros) realsense_ros ;;
    voice)         app_voice ;;
    colcon)        app_colcon ;;
    toolkit)       app_toolkit ;;
    *) echo "app-install: unknown subcommand '$1'" >&2; exit 2 ;;
esac
```

- [ ] **Step 2: 다섯 스크립트의 본문을 함수로 옮긴다**

| 원본 | 함수명 | 파일 최상단 상수 처리 |
|---|---|---|
| `dsr-project-install.sh` | `app_dsr()` | `WS_SRC` 를 함수 안 `local` 로 |
| `realsense-install.sh` | `realsense_sdk()` `realsense_ros()` | 이미 함수다. 원본 끝의 `case` 는 버린다 |
| `voice-host-install.sh` | `app_voice()` | `OWW_SRC="${SCRIPT_DIR}/oww_models"` 는 **최상단에 그대로 둔다** — `SCRIPT_DIR` 이 `resources/` 라 경로가 안 바뀐다. 함수 안 `local` 로 내려도 무방 |
| `colcon-build.sh` | `app_colcon()` | 최상단 상수 없음 |
| `nvidia-container-toolkit-install.sh` | `app_toolkit()` | 최상단 상수를 함수 안 `local` 로 |

`app_voice` 안에는 heredoc(`<<'PY' ... PY`)으로 된 python 블록이 있다. 들여쓰기를 바꾸면 안 된다 — `<<'PY'` 는 탭 제거를 안 하므로 종료 표지 `PY` 가 반드시 행 맨 앞에 있어야 한다. 함수 안으로 옮겨도 종료 표지는 들여쓰지 않는다.

- [ ] **Step 3: 원본 5개 삭제**

```bash
cd ~/rjt-refactor
git rm -q resources/dsr-project-install.sh resources/realsense-install.sh \
          resources/voice-host-install.sh resources/colcon-build.sh \
          resources/nvidia-container-toolkit-install.sh
git add resources/app-install.sh
```

- [ ] **Step 4: `setup-app.sh` 호출부 교체**

`do_workspace` (현 281-287줄):

```bash
    run "doosan-robot2 driver + DSR deps" bash "${RESOURCE_DIR}/app-install.sh" dsr
    run "RealSense SDK"                   bash "${RESOURCE_DIR}/app-install.sh" realsense-sdk
    run "RealSense ROS2 wrapper"          bash "${RESOURCE_DIR}/app-install.sh" realsense-ros
    run "host voice Python (direct)"      bash "${RESOURCE_DIR}/app-install.sh" voice
    run "colcon build"                    bash "${RESOURCE_DIR}/app-install.sh" colcon
```

`do_containers` (현 293줄):

```bash
    run "NVIDIA Container Toolkit" env ASSUME_YES=1 SKIP_IF_NO_GPU=1 bash "${RESOURCE_DIR}/app-install.sh" toolkit
```

**순서를 바꾸지 않는다.** voice 가 colcon 앞에 오는 것은 의도된 것이다 — colcon 이 voice 패키지를 system python 으로 빌드할 때 그 shebang 이 여기서 깐 의존성을 봐야 한다.

- [ ] **Step 5: 정적 검사 + 트레이스 비교**

```bash
cd ~/rjt-refactor && shellcheck resources/*.sh install.sh setup-app.sh && bash -n resources/*.sh
cd ~/ros2_jazzy_test && rm -rf .trace-after && bash scripts/trace-steps.sh ~/rjt-refactor .trace-after
diff -ru .trace-baseline .trace-after && echo "TRACE IDENTICAL"
```

Expected: 정적 검사 무출력 + `TRACE IDENTICAL`.

- [ ] **Step 6: `setup-app.sh --help` 확인**

```bash
cd ~/rjt-refactor && bash setup-app.sh --help >/dev/null && echo "SETUP-APP HELP OK"
```

Expected: `SETUP-APP HELP OK`.

- [ ] **Step 7: 커밋**

```bash
cd ~/rjt-refactor
git add -A
git commit -m "워크스페이스와 앱 계층 설치 다섯 개를 한 파일로 합침

로봇 드라이버 / 카메라 SDK / 카메라 ROS 래퍼 / 음성 파이썬 / 워크스페이스
빌드 / 컨테이너 툴킷은 모두 base 설치 다음 단계라 한 파일에서 서브커맨드로
고르는 편이 낫다.

설치 순서는 그대로다 — 음성 의존성이 워크스페이스 빌드보다 먼저 깔려야
빌드된 노드가 그 의존성을 본다."
```

---

### Task 5: `hostcfg.sh` — 호스트 런타임 설정 2개 병합

**Files:**
- Create: `~/rjt-refactor/resources/hostcfg.sh`
- Delete: `resources/dds-tuning.sh`, `resources/network-static-ip.sh`
- Modify: `~/rjt-refactor/install.sh:207,212`

**Interfaces:**
- Produces: `bash resources/hostcfg.sh <dds|network>`

- [ ] **Step 1: 새 파일 뼈대**

```bash
#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/hostcfg.sh — 설치가 끝난 호스트의 런타임 설정(DDS 버퍼 / 로봇 LAN 정적 IP).
# 설치가 아니라 설정이라 언제든 단독으로 다시 돌려도 된다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

# ... 함수 정의 — 다음 Step 의 표대로 원본 본문을 그대로 옮겨 온다 ...

case "${1:?hostcfg: subcommand required (dds|network)}" in
    dds)     hostcfg_dds ;;
    network) hostcfg_network ;;
    *) echo "hostcfg: unknown subcommand '$1'" >&2; exit 2 ;;
esac
```

`lib.sh` 는 source 하지 않는다 — 두 원본 모두 `add_apt_repo` 나 단계 엔진을 쓰지 않는다.

- [ ] **Step 2: 두 스크립트 본문을 함수로 옮긴다**

| 원본 | 함수명 | 최상단 상수 처리 |
|---|---|---|
| `dds-tuning.sh` | `hostcfg_dds()` | `TEMPLATE="${SCRIPT_DIR}/cyclonedds.xml.in"` 와 `SYSCTL_SRC="${SCRIPT_DIR}/sysctl-cyclonedds.conf"` 를 함수 안 `local` 로. **경로 문자열은 그대로** — `SCRIPT_DIR` 이 여전히 `resources/` 다 |
| `network-static-ip.sh` | `hostcfg_network()` | 최상단 상수 없음 |

- [ ] **Step 3: 원본 삭제 + `install.sh` 호출부 교체**

```bash
cd ~/rjt-refactor
git rm -q resources/dds-tuning.sh resources/network-static-ip.sh
git add resources/hostcfg.sh
```

`install.sh:207`:

```bash
run_step 8 dds_tuning bash "${RESOURCE_DIR}/hostcfg.sh" dds
```

`install.sh:212`:

```bash
run_step 9 network_static_ip bash "${RESOURCE_DIR}/hostcfg.sh" network
```

state 키 `dds_tuning` · `network_static_ip` 를 바꾸지 않는다.

`install.sh:206` 주석의 `bash resources/dds-tuning.sh` 안내 문구도 `bash resources/hostcfg.sh dds` 로 고친다.

- [ ] **Step 4: 정적 검사 + 트레이스 비교**

```bash
cd ~/rjt-refactor && shellcheck resources/*.sh install.sh setup-app.sh && bash -n resources/*.sh
cd ~/ros2_jazzy_test && rm -rf .trace-after && bash scripts/trace-steps.sh ~/rjt-refactor .trace-after
diff -ru .trace-baseline .trace-after && echo "TRACE IDENTICAL"
```

Expected: `TRACE IDENTICAL`.

- [ ] **Step 5: 커밋**

```bash
cd ~/rjt-refactor
git add -A
git commit -m "설치 후 호스트 설정 두 개를 한 파일로 합침

통신 버퍼 조정과 로봇 LAN 고정 주소 설정은 설치가 아니라 설정이라
성격이 같다. 언제든 단독으로 다시 돌려도 되는 것들이다."
```

---

### Task 6: 재개 런처를 `install.sh` 로 흡수

**Files:**
- Delete: `~/rjt-refactor/resources/install-resume-launcher.sh`
- Modify: `~/rjt-refactor/install.sh` (인자 처리 `case`), `resources/lib.sh` (`register_resume_autostart`)

**Interfaces:**
- Produces: `bash install.sh --resume-terminal` — 레포에서 `install.sh` 를 다시 돌리고 끝난 뒤 터미널을 열어 둔다. `usage()` 에는 노출하지 않는다.

- [ ] **Step 1: `install.sh` 인자 처리에 케이스 추가**

`install.sh:111-122` 의 `case` 에 `--help` 앞으로 넣는다:

```bash
    --resume-terminal)
        # 재부팅 뒤 GUI 자동시작이 부르는 내부 플래그. 설치를 다시 돌리고 결과를 볼 수 있게
        # 터미널을 열어 둔다. 도움말에는 안 보인다 — 사람이 직접 칠 일이 없다.
        cd "${SCRIPT_DIR}"
        rc=0; bash "$0" || rc=$?
        echo
        echo "[resume] install.sh exited (${rc}). Keeping this terminal open so you can review the result."
        # heartbeat 나 비밀번호 입력이 터미널 입력 상태를 흐트러뜨렸을 수 있어 되돌린다.
        stty sane 2>/dev/null || true
        exec bash
        ;;
```

주의: `install.sh` 는 최상단이 `set -euo pipefail` 이라 `bash "$0"` 이 실패하면 그 자리에서 죽는다. 그래서 `rc=0; ... || rc=$?` 로 받아야 터미널이 열린 채 남는다. 원본 런처가 `set -e` 를 안 켠 이유가 이것이다.

- [ ] **Step 2: `register_resume_autostart` 의 Exec 대상 교체**

`lib.sh` 안에서:

```bash
register_resume_autostart() {
    local repo="$1"
    local entry="${repo}/install.sh"
    local exec_line=""
    if command -v gnome-terminal >/dev/null; then
        exec_line="gnome-terminal -- bash \"${entry}\" --resume-terminal"
    elif command -v x-terminal-emulator >/dev/null; then
        exec_line="x-terminal-emulator -e bash \"${entry}\" --resume-terminal"
    else
        echo "[install] no terminal emulator — auto-resume not possible." >&2
        echo "             after reboot, run 'bash install.sh' manually." >&2
        return 0
    fi
    ...
```

나머지(heredoc 으로 `.desktop` 쓰는 부분)는 그대로 둔다. `Exec=` 의 인용 구조가 전과 같다 — 큰따옴표로 감싼 경로 하나 + 뒤에 공백 없는 플래그.

- [ ] **Step 3: 런처 삭제**

```bash
cd ~/rjt-refactor && git rm -q resources/install-resume-launcher.sh
```

- [ ] **Step 4: 생성되는 `.desktop` 이 올바른지 확인**

```bash
cd ~/rjt-refactor
HOME=/tmp/resume-check bash -c '
  mkdir -p /tmp/resume-check
  source resources/config.sh; source resources/lib.sh
  register_resume_autostart "$PWD"
  cat /tmp/resume-check/.config/autostart/ros2-jazzy-install-resume.desktop
'
rm -rf /tmp/resume-check
```

Expected: `Exec=` 줄이 아래 형태.

```
Exec=gnome-terminal -- bash "<레포경로>/install.sh" --resume-terminal
```

경로가 큰따옴표로 감싸져 있고 `--resume-terminal` 이 그 밖에 있어야 한다. 작은따옴표가 등장하면 안 된다.

터미널 에뮬레이터가 없는 머신이면 대신 `no terminal emulator` 경고가 나온다 — 그것도 정상이며, 그 경우 `Exec=` 확인은 건너뛴다.

- [ ] **Step 5: 정적 검사**

```bash
cd ~/rjt-refactor && shellcheck resources/*.sh install.sh setup-app.sh && bash -n resources/*.sh install.sh
```

Expected: 출력 없음.

- [ ] **Step 6: 커밋**

```bash
cd ~/rjt-refactor
git add -A
git commit -m "재부팅 후 자동 재개 런처를 설치 스크립트 안으로 넣음

파일 하나를 따로 둘 만큼 하는 일이 없었다. 설치 스크립트에 숨은 플래그로
넣고 자동시작 항목이 그 플래그를 부르게 했다.

자동시작 항목의 실행 줄 형태는 전과 같게 유지했다 — 그 규격은 작은따옴표를
인용으로 안 쳐서, 형태를 바꾸면 인자가 공백에서 쪼개져 조용히 깨진다."
```

---

### Task 7: `setup-app.sh` 가 공용 단계 러너를 쓰게 교체

**Files:**
- Modify: `~/rjt-refactor/setup-app.sh:100-169` (삭제), 호출부 전체

**Interfaces:**
- Consumes: Task 2 의 `run_step` + `STEP_STATE`.

- [ ] **Step 1: 중복 러너 3개 삭제**

`setup-app.sh` 의 `STEP_N=0` 선언과 `step()` `_hb()` `run()` 정의(100-169줄)를 통째로 지운다.

- [ ] **Step 2: `lib.sh` 러너를 쓰도록 전환**

`source` 줄 근처(Task 2 에서 이미 `lib.sh` 로 바뀌어 있다) 아래에 추가:

```bash
# setup-app 은 재개 개념이 없다 — 단계 결과를 state 에 남기지 않고 배너와 로그만 쓴다.
STEP_STATE=0
STEPS_TOTAL="${TOTAL}"
LOG_FILE="${LOG}"
```

`TOTAL` 과 `LOG` 는 `setup-app.sh` 가 이미 계산해 두는 변수다. `run_step` 은 `STEPS_TOTAL` 과 `LOG_FILE` 을 읽으므로 이어 준다.

호출부를 바꾼다. `run "<라벨>" <명령...>` → `run_step <번호> "<라벨>" <명령...>`. 번호는 원래 `STEP_N` 이 자동 증가시키던 것이라 이제 손으로 적는다.

`do_workspace`:

```bash
do_workspace() {
    run_step 1 "cobot2 source (verify)"          obtain_cobot2
    run_step 2 "m0609 bringup + onrobot-ros2"    obtain_m0609
    run_step 3 "doosan-robot2 driver + DSR deps" bash "${RESOURCE_DIR}/app-install.sh" dsr
    run_step 4 "RealSense SDK"                   bash "${RESOURCE_DIR}/app-install.sh" realsense-sdk
    run_step 5 "RealSense ROS2 wrapper"          bash "${RESOURCE_DIR}/app-install.sh" realsense-ros
    run_step 6 "host voice Python (direct)"      bash "${RESOURCE_DIR}/app-install.sh" voice
    run_step 7 "colcon build"                    bash "${RESOURCE_DIR}/app-install.sh" colcon
}
```

**동작 차이 주의**: 원래 `obtain_cobot2` / `obtain_m0609` 는 `step` 만 부르고 출력을 콘솔에 그대로 흘렸다(빠른 확인용). `run_step` 으로 감싸면 출력이 로그로 간다. 이 차이를 없애려면 두 줄을 `run_step` 대신 아래로 둔다:

```bash
    step_begin 1 "${TOTAL}" "cobot2 source (verify)"; obtain_cobot2; step_end DONE
    step_begin 2 "${TOTAL}" "m0609 bringup + onrobot-ros2"; obtain_m0609; step_end DONE
```

`STEP_STATE=0` 이므로 `step_begin`/`step_end` 는 배너만 찍고 state 를 안 건드린다. **이 형태를 쓴다** — 출력 동작을 바꾸지 않는 쪽이다.

`do_containers`:

```bash
do_containers() {
    run_step 8 "NVIDIA Container Toolkit" env ASSUME_YES=1 SKIP_IF_NO_GPU=1 bash "${RESOURCE_DIR}/app-install.sh" toolkit
    run_step 9 "build container image (yolo dev-builder)" bash "${SCRIPT_DIR}/containers/build-all.sh"
}
```

**번호 주의**: `setup-app.sh:97-99` 는 `TOTAL` 을 워크스페이스 7 + 컨테이너 2 로 계산하고, 원래는 `STEP_N` 이 실행되는 단계만 1부터 셌다. 고정 번호를 쓰면 `--containers-only` 일 때 `TOTAL=2` 인데 번호가 8·9로 나와 `[8/2]` 가 된다. 오프셋 변수를 둔다. `TOTAL` 계산 직후에:

```bash
# 컨테이너만 돌 때는 워크스페이스 7단계가 빠지므로 번호를 앞으로 당긴다.
STEP_OFF=0
[[ ${DO_WORKSPACE} -eq 1 ]] || STEP_OFF=-7
```

그리고 `do_containers` 안에서 `run_step $((8 + STEP_OFF))` / `$((9 + STEP_OFF))` 로 적는다. `--workspace-only` 는 1~7 이 그대로라 오프셋이 필요 없다.

- [ ] **Step 3: 정적 검사**

```bash
cd ~/rjt-refactor && shellcheck setup-app.sh && bash -n setup-app.sh
```

Expected: 출력 없음.

- [ ] **Step 4: 진행률 번호가 맞는지 확인 (실행 없이 배너만)**

```bash
cd ~/rjt-refactor
bash setup-app.sh --help >/dev/null && echo "HELP OK"
grep -n "run_step\|step_begin" setup-app.sh
```

Expected: `HELP OK` + 단계 호출 9개(워크스페이스 7 + 컨테이너 2)가 번호 순서대로.

- [ ] **Step 5: state 파일이 오염되지 않는지 확인**

`STEP_STATE=0` 이 실제로 먹는지 본다. 실제 설치를 돌리지 않고 러너만 시험한다:

```bash
cd ~/rjt-refactor
HOME=/tmp/stepstate-check bash -c '
  mkdir -p /tmp/stepstate-check
  source resources/config.sh; source resources/lib.sh
  STEP_STATE=0 STEPS_TOTAL=2 LOG_FILE=/tmp/stepstate-check/log
  run_step 1 demo true
  ls /tmp/stepstate-check/.ros2_jazzy_test/state 2>&1
'
rm -rf /tmp/stepstate-check
```

Expected: `[1/2] step: demo` 배너 + `[OK]` 뒤에 `No such file or directory` — **state 파일이 만들어지지 않아야 한다**.

state 파일이 생기면 `_state_ensure_file` 이 가드 밖에 남아 있는 것이다. `step_begin` / `run_step` 안의 `_state_ensure_file` 호출도 `STEP_STATE` 가드로 감싼다.

- [ ] **Step 6: 커밋**

```bash
cd ~/rjt-refactor
git add -A
git commit -m "앱 설치 스크립트가 공용 단계 실행기를 쓰도록 정리

배너 출력 / 살아있음 표시 / 로그 분리 / 실패 시 종료를 똑같이 하는 코드가
두 진입점에 각각 있었다. 공용 라이브러리 것 하나만 남긴다.

상태 기록은 끈 채로 쓴다 — 이쪽은 끊긴 지점부터 이어서 하는 개념이 없어
기록할 것이 없다."
```

---

### Task 8: `resources/` 주석 다이어트

**Files:**
- Modify: `~/rjt-refactor/resources/{config,activate,lib,base-install,app-install,hostcfg}.sh`

**Interfaces:**
- 코드 한 줄도 바꾸지 않는다. 주석만 줄인다.

- [ ] **Step 1: 대상 규모 확인**

```bash
cd ~/rjt-refactor
for f in resources/*.sh; do t=$(wc -l <"$f"); c=$(grep -cE '^\s*#' "$f"); echo "$f  총$t  주석$c"; done
```

- [ ] **Step 2: 파일별로 주석을 줄인다**

적용 규칙(Global Constraints 의 주석 항목과 같다):

1. 함수 위 Google-style 배너(`# Globals:` `# Arguments:` `# Outputs:` `# Returns:` 와 `####...####` 구분선)를 **전부 지우고** 한 줄 설명으로 바꾼다.
2. 한 문단 이상 이어지는 배경 설명은 What 한 줄 + Why 한 줄로 줄인다.
3. 결정 날짜·ADR 번호·단계 코드·룰 번호·폐기된 구조 이력을 지운다.
4. `docs/...` 파일명을 가리키는 포인터를 지운다.
5. 같은 사실을 각도만 바꿔 반복하는 문단을 하나로 합친다.
6. 도메인 용어는 첫 등장 시 한 번만 부연한다. bash 관용구는 설명하지 않는다.
7. 저작권 배너 4줄은 파일마다 남긴다.

`config.sh` NVIDIA 블록의 before/after 예시:

```bash
# --- NVIDIA 드라이버 -------------------------------------------------------
# 드라이버를 버전 + flavor 로 명시적으로 핀(버전 고정). 예전 `ubuntu-drivers install` 자동 선택은
# 머신/시점마다 다른 드라이버를 골랐고, 그 드라이버가 의존성으로 modules-extra 없는 반쪽 HWE 커널을
# 끌어와 재부팅 시 검은 화면(wifi/USB 입력 상실) 유발. 작업 머신에서 검증된 known-good 구성을
# 결정론적으로 재현하려고 핀.
#   설치 패키지 = nvidia-driver-${NVIDIA_DRIVER_VERSION}${NVIDIA_DRIVER_FLAVOR}
#   FLAVOR = "" (closed, 기본값) 또는 "-open" (open 커널 모듈).
#   closed 를 기본으로: Optimus(하이브리드) 노트북에서 -open + KMS 가 가끔 내장
#   패널 디스플레이를 못 켜서 검은 화면(gdm 세션 실패)이 나므로, 디스플레이가 더 안정적인 closed 로 핀.
#   VERSION 을 비워 두면 nvidia-driver-install.sh 가 ubuntu-drivers 자동 선택으로 폴백
#   (override 용 — 비결정성을 감수).
: "${NVIDIA_DRIVER_VERSION:=595}"
: "${NVIDIA_DRIVER_FLAVOR:=}"
```

→

```bash
# --- NVIDIA 드라이버 -------------------------------------------------------
# 설치 패키지 = nvidia-driver-${VERSION}${FLAVOR}. 자동 선택(ubuntu-drivers)은 머신마다 다른 걸
# 골라 재부팅 후 검은 화면이 난 적 있어 검증된 버전으로 고정한다. 비워 두면 자동 선택으로 돌아간다.
# FLAVOR: "" = closed(기본, 노트북 내장 패널에서 더 안정적), "-open" = open 커널 모듈.
: "${NVIDIA_DRIVER_VERSION:=595}"
: "${NVIDIA_DRIVER_FLAVOR:=}"
```

`lib.sh` 함수 주석 before/after 예시:

```bash
#######################################
# state 파일의 step_<name> 줄을 status 로 설정(없으면 추가, 있으면 교체).
# Globals:
#   STATE_FILE (읽기/쓰기)
# Arguments:
#   $1 - 단계 이름 name
#   $2 - 상태 status (DONE/FAIL/SKIPPED/RUNNING)
#######################################
_state_set() {
```

→

```bash
# state 파일의 step_<이름> 줄을 주어진 상태로 바꾼다(없으면 추가).
_state_set() {
```

- [ ] **Step 3: 금지 패턴이 남아 있지 않은지 확인**

```bash
cd ~/rjt-refactor
grep -nE "Globals:|Arguments:|Outputs:|Returns:|#{10,}" resources/*.sh
grep -nE "ADR-[0-9]|Hard Rule|사용자 결정 20|docs/[A-Za-z_]+\.md" resources/*.sh
```

Expected: 두 명령 모두 출력 없음.

- [ ] **Step 4: 코드가 안 바뀌었는지 확인 — 주석·공백 제거 후 비교**

```bash
cd ~/rjt-refactor
for f in resources/*.sh; do
  b=$(basename "$f")
  echo "=== $b"
  diff <(git show HEAD:"resources/$b" | grep -vE '^\s*#' | grep -vE '^\s*$') \
       <(grep -vE '^\s*#' "$f" | grep -vE '^\s*$') && echo "  code unchanged"
done
```

Expected: 파일마다 `code unchanged`.

차이가 나오면 주석을 지우다 코드 줄을 건드린 것이다. 되돌린다.

- [ ] **Step 5: `config.sh` 의 변수 계약이 그대로인지 확인**

이 태스크는 `config.sh` 도 건드리므로 환경변수 집합을 다시 본다. 주석만 지웠다면 완전히 같아야 한다.

```bash
cd ~/ros2_jazzy_test
diff <(bash -c 'set -a; source ~/rjt-main/resources/config.sh; declare -px' | sort) \
     <(bash -c 'set -a; source ~/rjt-refactor/resources/config.sh; declare -px' | sort) \
  && echo "CONFIG CONTRACT IDENTICAL"
```

Expected: `CONFIG CONTRACT IDENTICAL`.

- [ ] **Step 6: 정적 검사 + 트레이스 비교**

```bash
cd ~/rjt-refactor && shellcheck resources/*.sh && bash -n resources/*.sh
cd ~/ros2_jazzy_test && rm -rf .trace-after && bash scripts/trace-steps.sh ~/rjt-refactor .trace-after
diff -ru .trace-baseline .trace-after && echo "TRACE IDENTICAL"
```

Expected: `TRACE IDENTICAL`.

- [ ] **Step 7: 커밋**

```bash
cd ~/rjt-refactor
git add -A
git commit -m "설치 스크립트 주석을 읽기 쉬운 분량으로 줄임

한 결정의 배경을 문단으로 적어 둔 주석이 파일의 절반을 차지하고 있었다.
같은 내용이 별도 문서에도 있어서, 코드 옆에는 무엇을 하는지 한 줄과
왜 그렇게 했는지 한 줄만 남긴다.

함수마다 붙어 있던 인자·전역변수 목록 형식도 지웠다 — 함수 첫 줄이
이미 같은 것을 보여준다."
```

---

### Task 9: 진입점 2개 주석 다이어트

**Files:**
- Modify: `~/rjt-refactor/install.sh`, `~/rjt-refactor/setup-app.sh`

- [ ] **Step 1: 같은 규칙을 적용한다**

Task 8 Step 2 의 규칙 7개를 `install.sh` 와 `setup-app.sh` 에 그대로 적용한다.

`usage()` 안의 heredoc 은 **사용자에게 보이는 도움말이므로 건드리지 않는다**. 주석(`#` 로 시작하는 줄)만 대상이다.

- [ ] **Step 2: 금지 패턴 확인**

```bash
cd ~/rjt-refactor
grep -nE "Globals:|Arguments:|Outputs:|Returns:|#{10,}" install.sh setup-app.sh
grep -nE "ADR-[0-9]|Hard Rule|사용자 결정 20" install.sh setup-app.sh
```

Expected: 출력 없음.

`install.sh:195` 의 `docs/TROUBLESHOOTING.md` 언급은 **주석이 아니라 로그로 나가는 문자열**이다. 사용자에게 보이는 안내라 그대로 둔다.

- [ ] **Step 3: 코드 불변 확인**

```bash
cd ~/rjt-refactor
for f in install.sh setup-app.sh; do
  echo "=== $f"
  diff <(git show HEAD:"$f" | grep -vE '^\s*#' | grep -vE '^\s*$') \
       <(grep -vE '^\s*#' "$f" | grep -vE '^\s*$') && echo "  code unchanged"
done
```

Expected: 둘 다 `code unchanged`.

- [ ] **Step 4: 정적 검사 + 진입점 동작**

```bash
cd ~/rjt-refactor
shellcheck install.sh setup-app.sh && bash -n install.sh setup-app.sh
bash install.sh --help >/dev/null && bash setup-app.sh --help >/dev/null && bash install.sh --status && echo "ENTRYPOINTS OK"
```

Expected: `ENTRYPOINTS OK`.

- [ ] **Step 5: 커밋**

```bash
cd ~/rjt-refactor
git add -A
git commit -m "두 진입점 주석도 같은 기준으로 줄임

한쪽만 줄이면 같은 레포 안에서 주석 스타일이 갈린다. 사용자에게 보이는
도움말 문구는 그대로 두고 설명 주석만 손봤다."
```

---

### Task 10: `README.md` 정리 + `containers/` 참조 갱신

**Files:**
- Modify: `~/rjt-refactor/README.md:33-35` (삭제)
- Modify: `~/rjt-refactor/containers/bringup.sh:167`
- Modify: `~/rjt-refactor/containers/README.md:3`

- [ ] **Step 1: README 의 워크스페이스 rename 전환 안내 삭제**

`README.md` 에서 아래 인용 블록 3줄과 그 앞뒤 빈 줄을 지운다.

```markdown
> 워크스페이스 이름이 `~/cobot_ws` → `~/cobot2_ws` 로 바뀌었다. 옛 이름으로 이미 빌드해 둔 머신은
> `export DSR_WORKSPACE="$HOME/cobot_ws"` 로 기존 경로를 계속 쓰거나, 새 경로에서 다시 빌드한다
> (colcon `install/` 에는 절대 경로가 박혀 있어 디렉토리 rename 만으로는 오버레이가 깨진다).
```

`README.md` 의 다른 블록(`docker run` 원샷, RealSense 수동 기동, 68·75줄의 `resources/config.sh` 경로)은 건드리지 않는다.

- [ ] **Step 2: `containers/bringup.sh` 안내 문구 갱신**

167줄:

```bash
    echo "          (모델/의존성 점검: bash resources/app-install.sh voice)" >&2
```

이 파일에서 바꾸는 것은 이 한 줄뿐이다. 39줄의 `source "${REPO_DIR}/resources/config.sh"` 는 경로가 그대로다.

- [ ] **Step 3: `containers/README.md` 갱신**

3줄의 `` `resources/voice-host-install.sh` `` → `` `resources/app-install.sh voice` ``.

43줄의 `source resources/activate.sh` 는 경로가 안 바뀌므로 그대로 둔다.

- [ ] **Step 4: 옛 파일명이 남아 있지 않은지 확인**

```bash
cd ~/rjt-refactor
grep -rnE "resources/(kernel-baseline|nvidia-driver-install|docker-install|ros2-packages|vscode-install|dds-tuning|network-static-ip|dsr-project-install|realsense-install|colcon-build|voice-host-install|nvidia-container-toolkit-install|orchestrate|interaction|apt-repo|install-resume-launcher)\.sh" . --exclude-dir=.git
```

Expected: 출력 없음.

- [ ] **Step 5: 정적 검사**

```bash
cd ~/rjt-refactor && shellcheck containers/bringup.sh && bash -n containers/bringup.sh
```

Expected: 출력 없음.

- [ ] **Step 6: 최종 규모 확인**

```bash
cd ~/rjt-refactor
echo "resources/*.sh: $(cat resources/*.sh | wc -l)줄 ($(ls resources/*.sh | wc -l)개 파일)"
echo "install.sh: $(wc -l < install.sh)줄 / setup-app.sh: $(wc -l < setup-app.sh)줄"
```

Expected: `resources/*.sh` 6개 파일, 세 값의 합이 1300줄 아래(기준 2601줄).

- [ ] **Step 7: 커밋**

```bash
cd ~/rjt-refactor
git add -A
git commit -m "설치 안내에서 지난 이름 변경 메모를 빼고 바뀐 경로를 반영

옛 워크스페이스 이름으로 빌드해 둔 머신을 위한 임시 안내였는데, 새로
설치하는 사람에게는 읽을 이유가 없는 내용이다. 컨테이너 쪽 안내 문구가
가리키던 스크립트 경로도 합쳐진 이름으로 고쳤다."
```

---

### Task 11: 실기 스모크 + main 머지

**Files:** 없음 (검증과 통합만)

- [ ] **Step 1: 브랜치 push**

```bash
cd ~/rjt-refactor && git push -u origin refactor/resources-merge
```

- [ ] **Step 2: 대상 머신에서 브랜치 받기**

```bash
ssh -t 192.168.1.11 'cd ~/ros2_jazzy_test && git fetch origin refactor/resources-merge && git checkout refactor/resources-merge && git log --oneline -1'
```

Expected: 마지막 커밋 제목이 보인다.

- [ ] **Step 3: 스모크 — sudo 없는 것부터**

```bash
ssh -t 192.168.1.11 'cd ~/ros2_jazzy_test && bash install.sh --help >/dev/null && bash install.sh --status && bash setup-app.sh --help >/dev/null && echo SMOKE1_OK'
```

Expected: `SMOKE1_OK`.

- [ ] **Step 4: 스모크 — 환경 활성화**

```bash
ssh -t 192.168.1.11 'cd ~/ros2_jazzy_test && source resources/activate.sh && ros2 pkg list | head -3 && echo SMOKE2_OK'
```

Expected: 패키지 3개 + `SMOKE2_OK`.

- [ ] **Step 5: 스모크 — apt 단계 (비번 1회)**

```bash
ssh -t 192.168.1.11 'cd ~/ros2_jazzy_test && bash resources/base-install.sh kernel && bash resources/base-install.sh vscode && echo SMOKE3_OK'
```

Expected: apt 가 "already the newest version" 을 찍고 `SMOKE3_OK`. 이미 설치된 머신이라 새로 깔리는 패키지가 없어야 한다.

- [ ] **Step 6: 스모크 — DDS 설정이 같은 결과를 내는지**

```bash
ssh -t 192.168.1.11 'cp ~/.config/cyclonedds/cyclonedds.xml /tmp/dds-before.xml && cd ~/ros2_jazzy_test && bash resources/hostcfg.sh dds && diff /tmp/dds-before.xml ~/.config/cyclonedds/cyclonedds.xml && echo SMOKE4_OK'
```

Expected: `SMOKE4_OK` (diff 없음). 리팩토링 전에 생성된 XML 과 리팩토링 후가 같아야 한다.

`hostcfg.sh network` 는 돌리지 않는다.

- [ ] **Step 7: 대상 머신을 main 으로 되돌린다**

```bash
ssh -t 192.168.1.11 'cd ~/ros2_jazzy_test && git checkout main && git log --oneline -1'
```

- [ ] **Step 8: main 머지 + push**

브랜치가 `main` 기준이라 제외 경로가 섞이지 않는다. `merge-to-main.sh` 를 쓸 필요가 없다.

```bash
cd ~/ros2_jazzy_test
git checkout main
git merge --no-ff refactor/resources-merge -m "설치 스크립트를 역할별로 합치고 주석을 정리"
bash scripts/check-no-claude-on-main.sh main
git push origin main
```

Expected: `check-no-claude-on-main: 'main' clean`.

- [ ] **Step 9: dev 가 main 을 되받는다**

```bash
cd ~/ros2_jazzy_test
git checkout fix/dsr-clone-pin
git merge main
```

충돌이 나면 `resources/` 쪽은 **main 것을 택한다**(리팩토링 결과가 정답).

- [ ] **Step 10: worktree 정리**

```bash
cd ~/ros2_jazzy_test
git worktree remove ../rjt-refactor
git worktree remove ../rjt-main
```

---

### Task 12: 문서 참조 갱신 (dev 브랜치)

**Files:**
- Modify: `docs/COMPATIBILITY.md`, `docs/DEVELOPMENT_ROADMAP.md`, `docs/TROUBLESHOOTING.md`, `docs/CONTAINER_VS_HOST.md`, `docs/SCRIPTING_GUIDELINES.md`, `docs/TRAINEE_PRACTICE_PATH.md`, `CLAUDE.md`

Task 11 이 끝난 뒤(리팩토링이 main 과 dev 에 모두 들어간 뒤) 진행한다.

- [ ] **Step 1: 치환 대상 확인**

```bash
cd ~/ros2_jazzy_test
grep -rnE "resources/(kernel-baseline|nvidia-driver-install|docker-install|ros2-packages|vscode-install|dds-tuning|network-static-ip|dsr-project-install|realsense-install|colcon-build|voice-host-install|nvidia-container-toolkit-install|orchestrate|interaction|apt-repo|install-resume-launcher)\.sh" \
  docs/COMPATIBILITY.md docs/DEVELOPMENT_ROADMAP.md docs/TROUBLESHOOTING.md \
  docs/CONTAINER_VS_HOST.md docs/SCRIPTING_GUIDELINES.md docs/TRAINEE_PRACTICE_PATH.md CLAUDE.md | wc -l
```

Expected: 60 안팎.

- [ ] **Step 2: 기계적 치환**

```bash
cd ~/ros2_jazzy_test
FILES="docs/COMPATIBILITY.md docs/DEVELOPMENT_ROADMAP.md docs/TROUBLESHOOTING.md docs/CONTAINER_VS_HOST.md docs/SCRIPTING_GUIDELINES.md docs/TRAINEE_PRACTICE_PATH.md CLAUDE.md"
sed -i \
  -e 's#resources/kernel-baseline\.sh#resources/base-install.sh kernel#g' \
  -e 's#resources/nvidia-driver-install\.sh#resources/base-install.sh nvidia#g' \
  -e 's#resources/docker-install\.sh#resources/base-install.sh docker#g' \
  -e 's#resources/vscode-install\.sh#resources/base-install.sh vscode#g' \
  -e 's#resources/dds-tuning\.sh#resources/hostcfg.sh dds#g' \
  -e 's#resources/network-static-ip\.sh#resources/hostcfg.sh network#g' \
  -e 's#resources/dsr-project-install\.sh#resources/app-install.sh dsr#g' \
  -e 's#resources/voice-host-install\.sh#resources/app-install.sh voice#g' \
  -e 's#resources/colcon-build\.sh#resources/app-install.sh colcon#g' \
  -e 's#resources/nvidia-container-toolkit-install\.sh#resources/app-install.sh toolkit#g' \
  -e 's#resources/orchestrate\.sh#resources/lib.sh#g' \
  -e 's#resources/interaction\.sh#resources/lib.sh#g' \
  -e 's#resources/apt-repo\.sh#resources/lib.sh#g' \
  ${FILES}
```

`ros2-packages.sh` · `realsense-install.sh` · `install-resume-launcher.sh` 는 문맥에 따라 서브커맨드가 갈리므로 **손으로 고친다**:

| 옛 표기 | 새 표기 |
|---|---|
| `resources/ros2-packages.sh desktop` | `resources/base-install.sh ros2-desktop` |
| `resources/ros2-packages.sh extras` | `resources/base-install.sh ros2-extras` |
| `resources/ros2-packages.sh` (인자 없이) | `resources/base-install.sh ros2-desktop / ros2-extras` |
| `resources/realsense-install.sh sdk` | `resources/app-install.sh realsense-sdk` |
| `resources/realsense-install.sh ros` | `resources/app-install.sh realsense-ros` |
| `resources/install-resume-launcher.sh` | `install.sh --resume-terminal` |

- [ ] **Step 3: `docs/SCRIPTING_GUIDELINES.md` §6 을 다시 쓴다**

**이 문서가 지금은 리팩토링과 정반대를 지시하고 있다** — §8 이 Google `####` 블록을 강제하고 rationale 삭제를 금지한다. 경로 치환만 하면 다음에 스크립트를 고치는 사람이 지운 스타일을 도로 넣는다.

§6(55-97줄) 전체를 아래로 교체한다.

````markdown
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

- **파일 최상단에 상수를 두지 않는다.** 한 파일에 여러 서브커맨드가 살아서 이름이 겹치고, `set -u` 아래에서 남의 변수를 보게 된다. 함수 안 `local` 로 둔다.
- 서브커맨드는 별도 프로세스로 실행되므로 실패 시 `exit` 이 맞다. `return` 으로 바꾸지 않는다.
- 단계를 install.sh 시퀀스에 넣으려면 `resources/lib.sh` 의 스테이지 함수 + `STAGE_*_COUNT` 1곳만 갱신한다.
- **state 키(`run_step` 의 두 번째 인자)는 한 번 정하면 바꾸지 않는다.** 설치를 진행 중인 머신이 완료 단계를 다시 돈다.
````

- [ ] **Step 4: `docs/SCRIPTING_GUIDELINES.md` §7·§8 을 고친다**

§7(99-113줄)에서 파일명만 갱신한다.

- `ros2-packages.sh desktop|extras`, `realsense-install.sh sdk|ros` → `base-install.sh ros2-desktop|ros2-extras`, `app-install.sh realsense-sdk|realsense-ros`
- 112줄 `orchestrate.sh 의 run_step` → `lib.sh 의 run_step`

§8(115-125줄)의 117-123줄을 아래로 교체한다. 116줄(언어), 124줄(규칙 번호 인용 금지), 125줄(라이브러리 헤더)은 그대로 둔다.

````markdown
- **분량** — 블록당 무엇을 하는지 한 줄 + 왜 그런지 한 줄. 두 줄로 안 되면 코드가 복잡한 것이지 주석이 모자란 것이 아니다.
- **함수 주석** — 함수 위 한 줄. Google `####` 블록(`Globals:`/`Arguments:`/`Outputs:`/`Returns:`)은 쓰지 않는다. 인자는 함수 첫 줄의 `local a="$1" b="$2"` 가 이미 보여주고, 목록을 따로 두면 코드와 어긋난 채 남는다.
- **독자 수준** — 전공 지식은 있으나 이 도메인은 처음인 사람. 도메인 용어(RMW, DDS discovery, HWE 커널, DKMS, colcon overlay)는 첫 등장 시 한 번만 부연한다. bash 관용구(`set -euo pipefail`, `:=`, `${VAR:?}`)는 설명하지 않는다.
- **rationale** — 한 줄로 압축해 남긴다. 사고 경위를 문단으로 적지 않는다. 자세한 배경은 `docs/` 쪽 문서가 담당한다.
- **`docs/...` 링크를 주석에 넣지 않는다** — `docs/` 는 `main` 트리에 없어 공개 브랜치에서 죽은 참조가 된다. 근거를 직접 서술한다.
- **폐기된 구조의 이력을 적지 않는다** — "구 XXX 였고 …로 옮김" 류. 지금 무엇인지만 적는다.
````

- [ ] **Step 5: `CLAUDE.md` 갱신**

세 곳을 고친다.

- 23줄: `resources/{config,orchestrate,interaction,activate,apt-repo}.sh` → `resources/{config,lib,activate}.sh`
- 43줄: `해당 resources/<step>.sh 직접 실행` → `해당 서브커맨드 직접 실행(예: bash resources/base-install.sh vscode)`
- 44줄: `resources/orchestrate.sh`(state + run_step + step 정의 통합 엔진) → `resources/lib.sh`(state + run_step + step 정의 + 사용자 확인 + apt repo 등록 통합)

15줄의 `resources/config.sh` 와 45줄의 `shellcheck *.sh resources/*.sh scripts/*.sh` 는 그대로 둔다.

- [ ] **Step 6: 남은 옛 이름 확인**

```bash
cd ~/ros2_jazzy_test
grep -rnE "resources/(kernel-baseline|nvidia-driver-install|docker-install|ros2-packages|vscode-install|dds-tuning|network-static-ip|dsr-project-install|realsense-install|colcon-build|voice-host-install|nvidia-container-toolkit-install|orchestrate|interaction|apt-repo|install-resume-launcher)\.sh" \
  docs/COMPATIBILITY.md docs/DEVELOPMENT_ROADMAP.md docs/TROUBLESHOOTING.md \
  docs/CONTAINER_VS_HOST.md docs/SCRIPTING_GUIDELINES.md docs/TRAINEE_PRACTICE_PATH.md CLAUDE.md
```

Expected: 출력 없음.

`docs/MIGRATION_NOTES.md`(55건) · `docs/specs/` · `docs/plans/` · `docs/decisions/` 는 **고치지 않는다** — 당시 상태를 적은 기록이라 그때 파일명이 맞다.

- [ ] **Step 7: 커밋**

```bash
cd ~/ros2_jazzy_test
git add -A
git commit -m "문서가 가리키는 설치 스크립트 경로와 주석 규약을 갱신

스크립트를 합치면서 파일 이름이 바뀐 것을 반영하고, 스크립트 작성 규약이
지시하던 주석 형식도 새 기준에 맞췄다 — 규약을 안 고치면 다음에 손대는
사람이 방금 걷어낸 형식을 도로 넣는다.

과거 시점을 적은 기록 문서는 그대로 뒀다 — 그 시점에는 그 파일명이 맞았다."
```

---

## 완료 기준

- `resources/` 에 `.sh` 파일이 6개(`config` `activate` `lib` `base-install` `app-install` `hostcfg`)만 남는다.
- `bash scripts/trace-steps.sh` 전후 트레이스가 완전히 같다.
- `shellcheck` 가 `resources/*.sh` `install.sh` `setup-app.sh` `containers/bringup.sh` 에 대해 무출력.
- 192.168.1.11 스모크 4종(`SMOKE1_OK`~`SMOKE4_OK`) 통과.
- `bash scripts/check-no-claude-on-main.sh main` 통과.
- `resources/*.sh` + `install.sh` + `setup-app.sh` 합계가 1300줄 아래(기준 2601줄).
- 옛 파일명이 살아있는 문서 어디에도 남아 있지 않다(불변 기록 제외).
