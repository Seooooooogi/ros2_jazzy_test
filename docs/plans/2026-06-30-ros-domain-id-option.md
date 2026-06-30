# ROS_DOMAIN_ID 사용자 입력 옵션화 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 설치 시 대화형 prompt 로 `ROS_DOMAIN_ID` 를 받아 XDG config dir 에 영속화하고, host·두 컨테이너가 같은 값을 보게 한다.

**Architecture:** `config.sh` 가 영속 파일(`~/.config/ros2_jazzy_test/ros_domain_id`)을 디폴트로 읽는 단일 소스. `install.sh` 시작 단계가 `interaction.sh::prompt_domain_id` 로 값을 받아 파일에 기록. 컨테이너는 compose interpolation 으로, 인터랙티브 셸은 `dds-tuning.sh` 가 심는 `~/.bashrc` managed block 으로 같은 값을 본다.

**Tech Stack:** Bash (source-only 라이브러리 + 진입점 스크립트), shellcheck, ROS2 Jazzy / CycloneDDS.

## Global Constraints

- **단일 진실 소스**: `ROS_DOMAIN_ID` 값은 영속 파일 한 곳에만 저장, 모든 소비처는 `resources/config.sh` 경유. distro 단일 소스 원칙과 동형.
- **우선순위 고정**: 명시적 env override > 영속 파일 > 디폴트 `42`.
- **유효 범위**: 정수 `0–232` 만 수락(ROS2 도메인 ID 한계).
- **영속 위치**: `${XDG_CONFIG_HOME:-${HOME}/.config}/ros2_jazzy_test/ros_domain_id`. STATE_DIR 아님 → `install.sh --reset` 에도 보존(runtime config 분류, config.sh:136 철학).
- **`set -euo pipefail` 정책**: source 전용 라이브러리(`config.sh` / `interaction.sh` / `dds-tuning.sh`)에는 `set -e` 를 두지 않는다(호출자 셸 옵션 오염 방지). 진입점(`install.sh`)만 소유.
- **멱등성**: prompt 는 기존값을 디폴트로 재표시(Enter=유지), 파일 덮어쓰기. bashrc 는 managed block 재작성.
- **shellcheck 통과 필수** — 머지 전 `shellcheck *.sh resources/*.sh`.
- **커밋 정책**: 커밋은 사용자가 명시적으로 요청·승인했을 때만 실행한다. 각 Task 의 commit step 은 그 승인 하에서만 수행. commit message / 어디에도 AI attribution(Co-Authored-By 등) 금지 — 사용자 명의로만.

---

## File Structure

| 파일 | 책임 | 변경 |
|------|------|------|
| `resources/config.sh` | 단일 소스 — 경로 변수 + `ROS_DOMAIN_ID` 해석(env>파일>42) | Modify |
| `resources/interaction.sh` | `prompt_domain_id` 대화형 입력 + 영속 기록 | Modify (함수 추가) |
| `install.sh` | 시작 단계에서 `prompt_domain_id` 호출(첫 run 만) | Modify |
| `resources/dds-tuning.sh` | `~/.bashrc` managed block 에 `ROS_DOMAIN_ID` export | Modify |
| `.env.example`, `README.md`, `docs/COMPATIBILITY.md` | 안내 보정 | Modify |

**검증 격리 규약(모든 Task 공통):** config.sh 동작 검증은 실제 `~/.config` 를 건드리지 않도록 `XDG_CONFIG_HOME=/tmp/rdid_test` 로 격리한다. 테스트 후 `rm -rf /tmp/rdid_test`.

---

### Task 1: config.sh — 영속 파일을 디폴트로 읽기

**Files:**
- Modify: `resources/config.sh:164-166` (현 `ROS_DOMAIN_ID` 블록)

**Interfaces:**
- Produces: 환경변수 `ROS2_JAZZY_TEST_CONFIG_DIR`(XDG 하위 프로젝트 config 디렉토리 경로), `ROS_DOMAIN_ID`(해석된 최종 정수, export). 영속 파일 경로 = `${ROS2_JAZZY_TEST_CONFIG_DIR}/ros_domain_id`.

- [ ] **Step 1: 현재 동작 확인 (영속 파일이 무시됨을 먼저 본다)**

```bash
cd /home/rokey/ros2_jazzy_test
mkdir -p /tmp/rdid_test/ros2_jazzy_test && echo 15 > /tmp/rdid_test/ros2_jazzy_test/ros_domain_id
XDG_CONFIG_HOME=/tmp/rdid_test bash -c 'source resources/config.sh; echo "DOMAIN=$ROS_DOMAIN_ID"'
```
Expected (구현 전): `DOMAIN=42` — 파일을 읽지 않으므로 디폴트 42. (이것이 바꾸려는 동작.)

- [ ] **Step 2: config.sh 블록 교체**

`resources/config.sh` 의 현재 블록(164-166):
```sh
# ROS_DOMAIN_ID single source of truth. The host (activate.sh) and the two compose services must see the same
# value for discovery to work. Pinned explicitly so it is deterministic even in an unset shell.
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-42}"
```
를 다음으로 교체:
```sh
# ROS_DOMAIN_ID single source of truth. The host (activate.sh / interactive shell) and the two compose services
# must see the same value or DDS discovery silently fails. Resolution order: explicit env override > the
# install-time choice persisted on disk > 42. The persisted file (written by install.sh's prompt_domain_id)
# lives under the XDG config dir, NOT STATE_DIR, so wiping the installer state (--reset) does not silently
# reset the live domain — matching CYCLONEDDS_XML's "runtime config in XDG" policy above.
: "${ROS2_JAZZY_TEST_CONFIG_DIR:=${XDG_CONFIG_HOME:-${HOME}/.config}/ros2_jazzy_test}"
_domain_file="${ROS2_JAZZY_TEST_CONFIG_DIR}/ros_domain_id"
if [[ -z "${ROS_DOMAIN_ID:-}" && -r "${_domain_file}" ]]; then
    ROS_DOMAIN_ID="$(cat "${_domain_file}" 2>/dev/null)"
fi
unset _domain_file
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-42}"
```

- [ ] **Step 3: 우선순위 3케이스 검증**

```bash
cd /home/rokey/ros2_jazzy_test
# (a) env 최우선
XDG_CONFIG_HOME=/tmp/rdid_test ROS_DOMAIN_ID=7 bash -c 'source resources/config.sh; echo "a=$ROS_DOMAIN_ID"'
# (b) 파일 (env 없음)
XDG_CONFIG_HOME=/tmp/rdid_test bash -c 'source resources/config.sh; echo "b=$ROS_DOMAIN_ID"'
# (c) fallback (파일·env 없음)
rm -f /tmp/rdid_test/ros2_jazzy_test/ros_domain_id
XDG_CONFIG_HOME=/tmp/rdid_test bash -c 'source resources/config.sh; echo "c=$ROS_DOMAIN_ID"'
```
Expected: `a=7`, `b=15`, `c=42`.

- [ ] **Step 4: shellcheck + 정리**

```bash
shellcheck resources/config.sh && rm -rf /tmp/rdid_test
```
Expected: shellcheck 무경고, 종료 0.

- [ ] **Step 5: Commit (사용자 승인 시)**

```bash
git add resources/config.sh
git commit -m "config: ROS_DOMAIN_ID 를 영속 파일에서 읽도록 변경 — env > 파일 > 42"
```

---

### Task 2: interaction.sh — prompt_domain_id 함수

**Files:**
- Modify: `resources/interaction.sh` (파일 끝, sudo_prime 다음에 섹션 5 추가)

**Interfaces:**
- Consumes: `ROS2_JAZZY_TEST_CONFIG_DIR`, `ROS_DOMAIN_ID` (Task 1 의 config.sh 가 export — install.sh 가 config.sh 를 먼저 source).
- Produces: 함수 `prompt_domain_id`. 호출 후 영속 파일 기록 + 현재 셸 `ROS_DOMAIN_ID` export 갱신.

- [ ] **Step 1: 함수 추가**

`resources/interaction.sh` 끝(250행 `sudo_prime` 닫는 `}` 다음)에 추가:
```sh

# ============================================================================
# 5) domain-id — choose ROS_DOMAIN_ID interactively, persist under the XDG config dir
# ============================================================================
# Usage: prompt_domain_id   # call once at the start of install.sh, before the steps begin.
#
# host (activate.sh / interactive shell) and the two containers (compose) must all see the SAME
# ROS_DOMAIN_ID or DDS discovery silently fails. config.sh reads the persisted file as its default,
# so this is the single place a human chooses the value. config.sh must be sourced first so
# ROS_DOMAIN_ID / ROS2_JAZZY_TEST_CONFIG_DIR are already resolved when this runs.
#
# Idempotent: the current value (env > file > 42, already resolved by config.sh) is shown as the
# default and Enter keeps it. On a non-interactive shell there is no way to prompt — keep the current
# value and warn. Valid range: 0-232 (ROS2 domain id limit).
prompt_domain_id() {
    local file="${ROS2_JAZZY_TEST_CONFIG_DIR}/ros_domain_id"
    local current="${ROS_DOMAIN_ID:-42}"
    if [[ ! -t 0 ]]; then
        echo "[install] non-interactive shell — keeping ROS_DOMAIN_ID=${current} (edit ${file} to change)." >&2
        return 0
    fi
    local input=""
    while true; do
        read -r -p "ROS_DOMAIN_ID (DDS 도메인, 0-232) [기본 ${current}]: " input
        [[ -z "$input" ]] && input="$current"
        if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 0 && input <= 232 )); then
            break
        fi
        echo "  → 0-232 사이 정수만 입력하세요." >&2
    done
    mkdir -p "${ROS2_JAZZY_TEST_CONFIG_DIR}"
    printf '%s\n' "$input" > "${file}"
    export ROS_DOMAIN_ID="$input"
    echo "[install] ROS_DOMAIN_ID=${input} (저장: ${file})"
}
```

- [ ] **Step 2: 비대화형 fallback 검증 (파이프 = TTY 없음 → 파일 미생성)**

```bash
cd /home/rokey/ros2_jazzy_test
rm -rf /tmp/rdid_test
XDG_CONFIG_HOME=/tmp/rdid_test bash -c '
  source resources/config.sh; source resources/interaction.sh
  prompt_domain_id
  echo "after=$ROS_DOMAIN_ID"
' < /dev/null
test ! -e /tmp/rdid_test/ros2_jazzy_test/ros_domain_id && echo "OK: 파일 미생성"
```
Expected: 경고 메시지 + `after=42`, `OK: 파일 미생성` (비대화형은 prompt 도 기록도 안 함).

- [ ] **Step 3: 대화형 경로 수동 검증 (실제 터미널)**

> 자동화 불가(`read` 는 TTY 필요). 실제 터미널에서 1회:
```bash
cd /home/rokey/ros2_jazzy_test
XDG_CONFIG_HOME=/tmp/rdid_test bash -c 'source resources/config.sh; source resources/interaction.sh; prompt_domain_id'
# 프롬프트에 "300" 입력 → "0-232 사이 정수만" 재요구 확인
# 이어서 "15" 입력 → 저장 메시지 확인
cat /tmp/rdid_test/ros2_jazzy_test/ros_domain_id   # → 15
# 재실행 → "[기본 15]" 표시 확인(멱등), Enter → 15 유지
rm -rf /tmp/rdid_test
```
Expected: 범위 밖 재요구, 유효값 저장, 재실행 시 기존값이 디폴트.

- [ ] **Step 4: shellcheck**

```bash
shellcheck resources/interaction.sh
```
Expected: 무경고. (`(( ))` 산술/`read -r` 패턴 경고 없음 확인.)

- [ ] **Step 5: Commit (사용자 승인 시)**

```bash
git add resources/interaction.sh
git commit -m "interaction: ROS_DOMAIN_ID 대화형 입력 함수 추가 (0-232 검증 + XDG 영속)"
```

---

### Task 3: install.sh — 시작 단계에서 prompt_domain_id 호출

**Files:**
- Modify: `install.sh:144-158` (proceed-confirm / auto-resume 분기)

**Interfaces:**
- Consumes: `prompt_domain_id` (Task 2), `step_should_skip` / `confirm_or_abort` / `register_resume_autostart` (기존).

- [ ] **Step 1: 분기 재구성 — 첫 run 에만 prompt, resume 엔 skip**

`install.sh` 의 현재 블록(149-158):
```sh
if step_should_skip a01_reboot; then
    remove_resume_autostart
elif [[ -t 0 ]]; then
    confirm_or_abort "The install reboots once midway and auto-continues on return (login) (terminal auto-opens, one sudo password). Continue?"
    register_resume_autostart "${SCRIPT_DIR}"
else
    # Advisory warning → log only (console stays clean). Surfaces in install_log for diagnosis.
    { echo "[install] warning: non-interactive shell — cannot register auto-resume."
      echo "          Run it in a GUI session, or re-run 'bash install.sh' manually after reboot."; } >>"$LOG_FILE"
fi
```
를 다음으로 교체(resume 가 아닐 때 = 첫 run 에서만 도메인 선택; prompt_domain_id 가 비대화형/TTY 를 자체 처리하므로 양 분기 공통 1줄):
```sh
if step_should_skip a01_reboot; then
    # Resume after the step-6 reboot — the domain was already chosen on the first run.
    remove_resume_autostart
else
    # First run — collect the ROS_DOMAIN_ID choice up front (idempotent; non-interactive shells keep
    # the current value inside prompt_domain_id), then the reboot consent.
    prompt_domain_id
    if [[ -t 0 ]]; then
        confirm_or_abort "The install reboots once midway and auto-continues on return (login) (terminal auto-opens, one sudo password). Continue?"
        register_resume_autostart "${SCRIPT_DIR}"
    else
        # Advisory warning → log only (console stays clean). Surfaces in install_log for diagnosis.
        { echo "[install] warning: non-interactive shell — cannot register auto-resume."
          echo "          Run it in a GUI session, or re-run 'bash install.sh' manually after reboot."; } >>"$LOG_FILE"
    fi
fi
```

- [ ] **Step 2: 진입 시 prompt 노출 확인 (TTY 있는 셸에서, reboot 직전 abort)**

> reboot 를 실제로 실행하면 안 되므로 확인은 prompt 가 confirm 보다 먼저 뜨는지까지만. confirm 에 `n` 입력해 안전 종료.
```bash
cd /home/rokey/ros2_jazzy_test
# (실제 install 환경에서) bash install.sh
#   → "ROS_DOMAIN_ID (... 0-232) [기본 42]:" 가 reboot confirm 보다 먼저 출력되는지 확인
#   → 도메인 입력 후 confirm 에 n → "Aborted by user." 로 안전 종료(steps 미진입)
```
Expected: 도메인 prompt → reboot confirm 순서, `n` 으로 종료. (resume 상태에선 prompt 가 뜨지 않음.)

- [ ] **Step 3: shellcheck**

```bash
shellcheck install.sh
```
Expected: 무경고.

- [ ] **Step 4: Commit (사용자 승인 시)**

```bash
git add install.sh
git commit -m "install: 시작 단계에서 ROS_DOMAIN_ID 를 묻고 reboot 전에 확정 (resume 시 skip)"
```

---

### Task 4: dds-tuning.sh — ~/.bashrc managed block 에 ROS_DOMAIN_ID export

**Files:**
- Modify: `resources/dds-tuning.sh:117-124` (managed block heredoc + 완료 echo)

**Interfaces:**
- Consumes: `ROS_DOMAIN_ID` (dds-tuning 은 26행에서 config.sh 를 이미 source → 영속 파일값 반영).

- [ ] **Step 1: managed block 에 export 추가**

`resources/dds-tuning.sh` 의 heredoc(117-123)을:
```sh
{
    echo "${BEGIN_MARK}"
    echo "# CycloneDDS standard + large-topic buffer/interface tuning (managed by dds-tuning.sh, do not edit manually)"
    echo "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp"
    echo "export CYCLONEDDS_URI=\"file://${CYCLONEDDS_XML}\""
    echo "${END_MARK}"
} >> "${bashrc}"
echo "[dds] updated the ~/.bashrc managed block (CYCLONEDDS_URI / RMW_IMPLEMENTATION)"
```
로 수정(`ROS_DOMAIN_ID` export 한 줄 추가 + 완료 메시지 갱신):
```sh
{
    echo "${BEGIN_MARK}"
    echo "# CycloneDDS standard + large-topic buffer/interface tuning (managed by dds-tuning.sh, do not edit manually)"
    echo "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp"
    echo "export CYCLONEDDS_URI=\"file://${CYCLONEDDS_XML}\""
    echo "export ROS_DOMAIN_ID=${ROS_DOMAIN_ID}"
    echo "${END_MARK}"
} >> "${bashrc}"
echo "[dds] updated the ~/.bashrc managed block (CYCLONEDDS_URI / RMW_IMPLEMENTATION / ROS_DOMAIN_ID)"
```

- [ ] **Step 2: heredoc 이 도메인값을 박는지 정적 확인**

> dds-tuning.sh 전체 실행은 sysctl/NIC 탐지 등 부수효과가 커 위험. managed block 생성부만 검증한다.
```bash
cd /home/rokey/ros2_jazzy_test
grep -n "export ROS_DOMAIN_ID=\${ROS_DOMAIN_ID}" resources/dds-tuning.sh
```
Expected: 한 줄 매치(heredoc 안). 실제 `~/.bashrc` 반영은 사용자 머신 통합 테스트(아래 최종 검증)에서.

- [ ] **Step 3: shellcheck**

```bash
shellcheck resources/dds-tuning.sh
```
Expected: 무경고.

- [ ] **Step 4: Commit (사용자 승인 시)**

```bash
git add resources/dds-tuning.sh
git commit -m "dds-tuning: ~/.bashrc 관리 블록에 ROS_DOMAIN_ID export 추가 — 인터랙티브 셸 도메인 일치"
```

---

### Task 5: 문서/예시 보정

**Files:**
- Modify: `.env.example:21-22`, `README.md`(ROS_DOMAIN_ID 안내), `docs/COMPATIBILITY.md:91,143`

- [ ] **Step 1: .env.example 갱신**

`.env.example` 의 21-22행:
```
# ROS_DOMAIN_ID=42           # host ↔ 컨테이너 DDS discovery 동일 도메인. 단일 진실 소스 = resources/config.sh(기본 42).
#                            # 비워두면 host·compose 둘 다 42 사용. 값을 바꾸려면 반드시 host·양 컨테이너 동일 — 다르면 조용한 discovery 실패
```
를:
```
# ROS_DOMAIN_ID=             # host ↔ 컨테이너 DDS discovery 동일 도메인. 설치 시 install.sh 가 prompt 로 물어
#                            # ~/.config/ros2_jazzy_test/ros_domain_id 에 저장(기본 42). config.sh 가 그 파일을 디폴트로 읽음.
#                            # 여기에 값을 주면 그 세션 env 가 최우선 — host·양 컨테이너 동일해야 함(다르면 조용한 discovery 실패).
```

- [ ] **Step 2: README.md — config.sh 설명 보정**

`README.md:76` 의:
```
> - `config.sh` 가 단일 진실 소스라 `ROS_DOMAIN_ID=42` · `RMW` · `CYCLONEDDS` 를 한꺼번에 세팅한다. 이걸 빠뜨린 셸은 도메인 0 으로 떨어져 컨테이너(도메인 42) 토픽/서비스를 **조용히 미발견**한다.
```
를(42 고정 표현 → 설치 시 선택):
```
> - `config.sh` 가 단일 진실 소스라 `ROS_DOMAIN_ID`(설치 시 prompt 로 선택, 기본 42) · `RMW` · `CYCLONEDDS` 를 한꺼번에 세팅한다. 이걸 빠뜨린 셸은 도메인 0 으로 떨어져 컨테이너 토픽/서비스를 **조용히 미발견**한다.
```

- [ ] **Step 3: README.md — docker run 예시 주석 일반화**

`README.md` 의 docker run 예시 3곳(149 / 184 / 199 부근)의 `-e ROS_DOMAIN_ID=42 \` 줄 뒤 주석을 "(설치 시 고른 값과 동일해야 함; 기본 42)"로 보정. 예:
```
  -e ROS_DOMAIN_ID=42 -e RMW_IMPLEMENTATION=rmw_cyclonedds_cpp \   # 42 = 설치 시 고른 값(기본). host 와 동일해야 discovery 성립
```
값 자체(`42`)는 예시로 유지하되 "설치 시 고른 값" 임을 주석에 명시. 221행(venv 데모 export 예시)도 동일 취지 주석 1줄 추가.

- [ ] **Step 4: docs/COMPATIBILITY.md 부기**

`docs/COMPATIBILITY.md` 의 91행·143행에 등장하는 `ROS_DOMAIN_ID`(기본 42) 표현 뒤에 "(설치 시 prompt 로 선택)" 를 부기. 매트릭스 값/구조는 변경하지 않음.

- [ ] **Step 5: 정적 확인**

```bash
cd /home/rokey/ros2_jazzy_test
grep -n "ROS_DOMAIN_ID" .env.example README.md docs/COMPATIBILITY.md | grep -i "설치 시\|prompt"
```
Expected: .env.example / README / COMPATIBILITY 각각에 "설치 시" 또는 "prompt" 문구 매치.

- [ ] **Step 6: Commit (사용자 승인 시)**

```bash
git add .env.example README.md docs/COMPATIBILITY.md
git commit -m "문서: ROS_DOMAIN_ID 가 설치 시 선택값임을 안내 (예시/매트릭스 보정)"
```

---

## 최종 통합 검증 (사용자 머신, 실측)

> 실제 `~/.bashrc` / 컨테이너 반영은 자동 테스트 범위 밖 — 설치 머신에서 1회 확인.

- [ ] config.sh 단위: `XDG_CONFIG_HOME` 격리 3케이스(env/파일/42) — Task 1 Step 3 재실행.
- [ ] 실 셸: `bash install.sh` → 도메인 입력(예 30) → (전체 설치 또는 dds_tuning step 까지) → 새 터미널에서 `echo $ROS_DOMAIN_ID` = `30`, `grep ROS_DOMAIN_ID ~/.bashrc` 매치.
- [ ] 컨테이너 일치: `set -a; source resources/config.sh; set +a; docker compose -f containers/docker-compose.yml config | grep ROS_DOMAIN_ID` → 세 서비스 모두 `30`.
- [ ] `--reset` 보존: `bash install.sh --reset` 후 `cat ~/.config/ros2_jazzy_test/ros_domain_id` = `30` 유지(STATE_DIR 분리 확인).
- [ ] 전체 shellcheck: `shellcheck *.sh resources/*.sh scripts/*.sh` 무경고.

---

## Self-Review (작성자 체크)

- **Spec coverage**: spec §4.1 영속 저장 → Task 1; §4.2 config.sh 읽기 → Task 1; §4.3 prompt → Task 2+3; §4.4 dds-tuning → Task 4; §4.5 문서 → Task 5; §7 검증 → 각 Task 검증 step + 최종 통합. 누락 없음.
- **Placeholder scan**: TBD/TODO 없음. 모든 코드 step 에 실제 코드 포함. 대화형 `read` 만 수동 검증으로 명시(자동화 불가 사유 기재).
- **Type/이름 일관성**: `ROS2_JAZZY_TEST_CONFIG_DIR`(Task1 정의 → Task2 소비), `prompt_domain_id`(Task2 정의 → Task3 호출), 영속 파일명 `ros_domain_id` 전 Task 동일. 일치.
