#!/usr/bin/env bash
# shellcheck shell=bash
# resources/interaction.sh — 설치 UX/secret 헬퍼 (.env 로더 + confirm 프롬프트 + 무인 설치).
# source 전용 라이브러리 — set -euo 를 여기 두지 않는다(호출 진입점이 셸 옵션을 소유).
#
# 세 관심사를 한 파일로 묶는다 — 모두 "사람/자격증명과의 상호작용" 이라는 한 축:
#   1) env-load   — .env 자격증명을 스크립트에 박지 않고 안전 로드/기록 (source 미사용 수동 파싱).
#   2) confirm    — 되돌릴 수 없는 작업(reboot / purge / driver swap) 전 명시 동의.
#   3) unattended — 무인 설치(--unattended): 자격증명 선수집 + reboot 후 GUI autostart 자동 재개.
#
# unattended 섹션은 아래 env-load 함수(_load_env/_set_env_key/_relocate_example_secret)를 쓴다.
# 함수는 call-time resolve 라 정의 순서만 맞으면 되고, 호출자 source 순서와 무관.

# ============================================================================
# 1) env-load — Safe .env loader (자격증명을 스크립트에 박지 않고 .env 에서 로드)
# ============================================================================
# Usage:
#   _load_env "${HOME}/ros2_jazzy_test/.env"
#   _require_env OPENAI_API_KEY
#   # 이후 ${OPENAI_API_KEY} 사용 가능. 절대 값을 echo / log 하지 않는다.
#
# Format: 한 줄당 KEY=VALUE. 빈 줄과 # 주석 무시. quote 미지원 (단순 형식).
# Security: `source` 사용 안 함 (악성 .env 파일이 쉘 명령 실행 차단). 수동 파싱.

_load_env() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "env-load: file not found: $file" >&2
        return 1
    fi

    # Permission warning: .env 가 world-readable 이면 경고만 출력 (강제 chmod 하지 않음).
    if [[ "$(stat -c %a "$file" 2>/dev/null)" == *[4-7] ]]; then
        echo "env-load: warning — $file is world-readable. Consider chmod 600." >&2
    fi

    local key value
    while IFS='=' read -r key value; do
        # 빈 줄 / 주석 skip
        [[ -z "${key// }" || "$key" =~ ^[[:space:]]*# ]] && continue
        # trim leading/trailing whitespace from key
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        # 변수명 검증 (보안: 임의 변수 주입 차단)
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        # 값 export (quote 처리 없음 — .env 에 quote 쓰지 않는 컨벤션)
        export "${key}=${value}"
    done < "$file"
}

# Public: 필수 변수가 비어 있으면 에러. 값 자체는 절대 출력 안 함.
_require_env() {
    local var="$1"
    if [[ -z "${!var:-}" ]]; then
        echo "env: required variable '$var' is empty (set in .env or environment)" >&2
        return 1
    fi
}

# Public: .env 의 KEY 를 VALUE 로 설정 (있으면 교체, 없으면 추가). 값은 절대 출력하지 않는다.
# 주석 처리된 '# KEY=' 라인도 활성 'KEY=VALUE' 로 교체한다.
# 값을 sed/awk 등 외부 명령 인자로 넘기지 않는다(순수 bash) — API 키의 특수문자 깨짐과
# `ps` 프로세스 목록 노출을 동시에 차단. 임시파일은 .env 옆(동일 fs)에 600 으로 만들어
# 원자적 rename 으로 교체하고, /tmp 경유로 비밀이 새지 않게 한다.
_set_env_key() {
    local file="$1" key="$2" value="$3"
    # 변수명 검증 — 임의 키 주입 차단 (_load_env 와 동일 정책). 값은 절대 출력하지 않는다.
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "env-load: invalid key name" >&2; return 1; }
    local tmp line found=0
    tmp="$(mktemp "${file}.XXXXXX")" || return 1
    chmod 600 "$tmp"
    if [[ -f "$file" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^[[:space:]]*#?[[:space:]]*"${key}"= ]]; then
                printf '%s=%s\n' "$key" "$value" >> "$tmp"
                found=1
            else
                printf '%s\n' "$line" >> "$tmp"
            fi
        done < "$file"
    fi
    [[ "$found" -eq 0 ]] && printf '%s=%s\n' "$key" "$value" >> "$tmp"
    mv "$tmp" "$file"
    chmod 600 "$file"
}

# Public: 추적 파일(.env.example)에 실수로 넣은 실제 KEY 값을 .env 로 옮기고 example 은
# placeholder 로 복원한다. .env.example 은 git 추적 대상이라 실제 값이 남으면 secret 유출.
# 값은 절대 화면/로그에 출력하지 않는다. 멱등 — example 에 값이 없으면 아무것도 안 한다.
# 인자: <env_file> <env_example> <key>
_relocate_example_secret() {
    local env_file="$1" example="$2" key="$3"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "env-load: invalid key name" >&2; return 1; }
    [[ -f "$example" ]] || return 0
    # example 에서 값이 있는('=' 뒤 내용 존재) KEY 줄을 찾는다(주석 처리 여부 무관). 값 미출력.
    local line val
    line="$(grep -E "^[[:space:]]*#?[[:space:]]*${key}=.+" "$example" 2>/dev/null | head -1)" || true
    [[ -z "$line" ]] && return 0
    val="${line#*=}"
    [[ "$val" =~ ^[[:space:]]*$ ]] && return 0   # 빈/공백 placeholder 는 무시
    echo "env-load: 경고 — 추적 파일 ${example} 에 ${key} 의 실제 값이 있습니다(secret 유출 위험)." >&2
    echo "          ${env_file} 로 옮기고 ${example} 을 placeholder 로 되돌립니다(값 미표시)." >&2
    # .env 보장 후 키 이전(_set_env_key 는 값을 출력하지 않음).
    [[ -f "$env_file" ]] || { : > "$env_file"; chmod 600 "$env_file"; }
    _set_env_key "$env_file" "$key" "$val"
    # example 의 해당 줄을 빈 placeholder('# KEY=')로 복원해 값 제거.
    local tmp l
    tmp="$(mktemp "${example}.XXXXXX")" || return 1
    chmod 600 "$tmp"
    while IFS= read -r l || [[ -n "$l" ]]; do
        if [[ "$l" =~ ^[[:space:]]*#?[[:space:]]*${key}= ]]; then
            printf '# %s=\n' "$key" >> "$tmp"
        else
            printf '%s\n' "$l" >> "$tmp"
        fi
    done < "$example"
    mv "$tmp" "$example"
    echo "env-load: ${key} 이전 완료 — 노출됐던 키는 rotate 를 권장합니다." >&2
}

# ============================================================================
# 2) confirm — 되돌릴 수 없는 작업(state-changing) 전 명시 동의
# ============================================================================
# (sudo reboot / apt purge / driver swap 등 되돌릴 수 없는 작업은 사용자 명시 동의 필수).
#
# Usage:
#   confirm_or_abort "Reboot now? Unsaved work will be lost."
#
# Default: N. 오직 [yY] 만 진행. Non-interactive 셸 (TTY 없음) 에서는 안전하게 abort.

confirm_or_abort() {
    local msg="$1"
    local reply=""

    # Non-interactive 셸 (CI / cron / systemd) 에서는 default N — 사용자 결정 없이 진행 금지.
    if [[ ! -t 0 ]]; then
        echo "confirm: non-interactive shell, aborting." >&2
        echo "        msg: $msg" >&2
        exit 1
    fi

    read -p "${msg} (y/N): " -n 1 -r reply
    echo
    if [[ ! "$reply" =~ ^[yY]$ ]]; then
        echo "Aborted by user."
        exit 0
    fi
}

# Public: 같은 메시지를 다시 묻고 싶지 않을 때 — 환경변수 ASSUME_YES=1 이면 자동 동의.
# CI / 자동화 wrapper 가 명시적으로 동의를 표현하는 통로.
confirm_or_abort_assumable() {
    local msg="$1"
    if [[ "${ASSUME_YES:-0}" == "1" ]]; then
        echo "${msg} (auto-confirmed via ASSUME_YES=1)"
        return 0
    fi
    confirm_or_abort "$msg"
}

# ============================================================================
# 3) unattended — 무인 설치(--unattended) 헬퍼
# ============================================================================
# 시작 시 자격증명(OPENAI_API_KEY) 선수집 + reboot 후 GUI autostart 로 install.sh 자동 재개.
# 위 env-load 섹션(_load_env/_require_env/_set_env_key/_relocate_example_secret)을 사용한다.
#
# 메커니즘: GNOME autostart(.desktop)가 로그인 시 터미널을 열어 install-resume-launcher.sh
# 를 실행 → install.sh --unattended 재기동. install.sh 가 재개 진입 시 autostart 를 즉시
# 제거(one-shot)해 로그인마다 재발화하지 않게 한다.

UNATTENDED_AUTOSTART_DIR="${HOME}/.config/autostart"
UNATTENDED_AUTOSTART_FILE="${UNATTENDED_AUTOSTART_DIR}/ros2-jazzy-install-resume.desktop"

# OPENAI_API_KEY 를 미리 받아 .env 에 기록 → reboot 후 step12(voice)가 비대화로 통과.
# 값은 화면/로그에 출력하지 않는다(read -s). 이미 설정돼 있으면 통과.
unattended_collect_secrets() {
    local repo="$1"
    local env_file="${repo}/.env" env_example="${repo}/.env.example"
    if [[ ! -f "${env_file}" ]]; then
        if [[ -f "${env_example}" ]]; then
            cp "${env_example}" "${env_file}"; chmod 600 "${env_file}"
            echo "[unattended] .env 생성(.env.example 복사)." >&2
        else
            echo "[unattended] .env / .env.example 둘 다 없음 — 자격증명 템플릿 필요." >&2
            return 1
        fi
    fi
    # 추적 파일(.env.example)에 실제 키가 있으면 .env 로 옮기고 example 복원(secret 방지).
    _relocate_example_secret "${env_file}" "${env_example}" OPENAI_API_KEY
    # 키 존재 판단은 .env 파일 내용으로(쉘 env 아님) — 컨테이너는 .env 만 읽는다.
    if grep -qE '^[[:space:]]*OPENAI_API_KEY=.+' "${env_file}"; then
        echo "[unattended] OPENAI_API_KEY 확인됨 (.env) — voice step 비대화 통과." >&2
        return 0
    fi
    echo "[unattended] OPENAI_API_KEY 입력(화면 미표시, 비우고 Enter=건너뜀):" >&2
    printf '  OPENAI_API_KEY: ' >&2
    local key=""
    read -rs key; echo >&2
    if [[ -n "${key}" ]]; then
        _set_env_key "${env_file}" OPENAI_API_KEY "${key}"
        echo "[unattended] .env 에 저장." >&2
    else
        echo "[unattended] 건너뜀 — reboot 후 voice step 에서 다시 묻습니다(자동 재개가 거기서 멈춤)." >&2
    fi
    return 0
}

# reboot 후 자동 재개 등록: 로그인 시 터미널에서 install-resume-launcher.sh 기동.
unattended_register_resume() {
    local repo="$1"
    local launcher="${repo}/resources/install-resume-launcher.sh"
    local exec_line=""
    if command -v gnome-terminal >/dev/null; then
        exec_line="gnome-terminal -- bash \"${launcher}\""
    elif command -v x-terminal-emulator >/dev/null; then
        exec_line="x-terminal-emulator -e bash \"${launcher}\""
    else
        echo "[unattended] 터미널 에뮬레이터 없음 — 자동 재개 불가." >&2
        echo "             reboot 후 'bash install.sh --unattended' 를 수동 실행하세요." >&2
        return 0
    fi
    mkdir -p "${UNATTENDED_AUTOSTART_DIR}"
    cat > "${UNATTENDED_AUTOSTART_FILE}" <<EOF
[Desktop Entry]
Type=Application
Name=ros2_jazzy_test install resume
Comment=클린설치 reboot 후 install.sh 자동 재개 (1회용)
Exec=${exec_line}
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
    echo "[unattended] reboot 후 자동 재개 등록: ${UNATTENDED_AUTOSTART_FILE}" >&2
}

# autostart 항목 제거(멱등) — 재개 진입 시(one-shot 보장) 및 완료 시 호출.
unattended_remove_resume() {
    if [[ -f "${UNATTENDED_AUTOSTART_FILE}" ]]; then
        rm -f "${UNATTENDED_AUTOSTART_FILE}"
        echo "[unattended] 자동 재개 항목 제거: ${UNATTENDED_AUTOSTART_FILE}" >&2
    fi
    return 0
}
