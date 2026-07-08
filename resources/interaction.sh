#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck shell=bash
# resources/interaction.sh — 설치 UX/secret 헬퍼 (.env 로더 + confirm 프롬프트 + 재개용 autostart).
# source 전용 라이브러리 — set -euo 를 여기 두지 않는다(호출 진입점이 셸 옵션을 소유).
#
# 한 파일에 세 가지 관심사를 묶음 — 모두 "사람/자격증명과의 상호작용" 이라는 한 축:
#   1) env-load   — .env 자격증명을 스크립트에 하드코딩하지 않고 안전하게 로드/기록 (수동 파싱, source 안 씀).
#                   openai-key-setup.sh 가 사용 (컨테이너 셋업 중 setup-app.sh 가 실행) — _set_env_key/_relocate_example_secret.
#   2) confirm    — 되돌릴 수 없는 작업 (reboot / purge / 드라이버 교체) 전 명시적 동의.
#   3) resume     — 일회성 GUI autostart 항목 등록/제거 → step-6 reboot 후 install.sh 가 자동 재개.
#
# 함수는 호출 시점(call time)에 해석 → 정의 순서만 중요, 호출자의 source 순서와 무관.

# ============================================================================
# 1) env-load — 안전한 .env 로더 (자격증명을 스크립트에 하드코딩하는 대신 .env 에서 로드)
# ============================================================================
# 사용법:
#   _load_env "${HOME}/ros2_jazzy_test/.env"
#   _require_env OPENAI_API_KEY
#   # 이후 ${OPENAI_API_KEY} 사용 가능. 값을 절대 echo / log 하지 말 것.
#
# 형식: 한 줄에 KEY=VALUE. 빈 줄과 # 주석은 무시. 따옴표(quote) 미지원 (단순 형식).
# 보안: source 안 씀 (악의적 .env 파일이 셸 명령을 실행하는 것을 차단). 수동 파싱.

_load_env() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "env-load: file not found: $file" >&2
        return 1
    fi

    # 권한 경고: .env 를 누구나 읽을 수 있으면(world-readable) 경고만 (강제로 chmod 하지 않음).
    if [[ "$(stat -c %a "$file" 2>/dev/null)" == *[4-7] ]]; then
        echo "env-load: warning — $file is world-readable. Consider chmod 600." >&2
    fi

    local key value
    while IFS='=' read -r key value; do
        # 빈 줄 / 주석은 건너뜀
        [[ -z "${key// }" || "$key" =~ ^[[:space:]]*# ]] && continue
        # key 앞뒤 공백 제거
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        # 변수 이름 검증 (보안: 임의 변수 주입 차단)
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        # 값을 export (따옴표 처리 없음 — .env 에는 따옴표를 안 쓰는 게 관례)
        export "${key}=${value}"
    done < "$file"
}

# 필수 변수가 비어 있으면 에러로 알림. 값 자체는 절대 미출력.
_require_env() {
    local var="$1"
    if [[ -z "${!var:-}" ]]; then
        echo "env: required variable '$var' is empty (set in .env or environment)" >&2
        return 1
    fi
}

#######################################
# .env 안의 KEY 를 VALUE 로 설정 (있으면 교체, 없으면 뒤에 추가). 값은 절대 미출력.
# 주석 처리된 '# KEY=' 줄도 활성 'KEY=VALUE' 로 교체.
# 값을 sed/awk 같은 외부 명령의 인자로 안 넘김 (순수 bash) — API 키가 특수문자로 깨지는 것과
# `ps` 프로세스 목록에 노출되는 것을 둘 다 차단. 임시 파일은 .env 옆(같은 파일시스템)에 mode 600
# 으로 만들고 atomic rename(원자적 교체)으로 바꿔치기 → /tmp 를 거쳐 secret 이 새지 않게 함.
# Arguments:
#   $1 - .env 파일 경로
#   $2 - 설정할 KEY 이름
#   $3 - 설정할 값 (출력 금지)
#######################################
_set_env_key() {
    local file="$1" key="$2" value="$3"
    # 변수 이름 검증 — 임의 key 주입 차단 (_load_env 와 동일 정책). 값은 절대 미출력.
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

#######################################
# 추적 대상 파일(.env.example)에 실수로 들어간 진짜 KEY 값을 .env 로 이동 + example 은 다시
# placeholder 로 복원. .env.example 은 git 추적 대상 → 진짜 값이 남으면 secret 유출.
# 값은 화면/로그에 절대 미출력. 멱등 — example 에 값 없으면 no-op.
# Arguments:
#   $1 - .env 파일 경로 (env_file)
#   $2 - .env.example 파일 경로 (example)
#   $3 - 대상 KEY 이름
#######################################
_relocate_example_secret() {
    local env_file="$1" example="$2" key="$3"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "env-load: invalid key name" >&2; return 1; }
    [[ -f "$example" ]] || return 0
    # example 에서 값이 있는(= 뒤에 내용이 있는) KEY 줄을 탐색 (주석 여부 무관). 값은 미출력.
    local line val
    line="$(grep -E "^[[:space:]]*#?[[:space:]]*${key}=.+" "$example" 2>/dev/null | head -1)" || true
    [[ -z "$line" ]] && return 0
    val="${line#*=}"
    [[ "$val" =~ ^[[:space:]]*$ ]] && return 0   # 빈 값/공백뿐인 placeholder 는 무시
    echo "env-load: warning — the tracked file ${example} contains a real value for ${key} (secret-leak risk)." >&2
    echo "          Moving it to ${env_file} and restoring ${example} to a placeholder (value not shown)." >&2
    # .env 가 있는지 보장한 뒤 키 이동 (_set_env_key 는 값 미출력).
    [[ -f "$env_file" ]] || { : > "$env_file"; chmod 600 "$env_file"; }
    _set_env_key "$env_file" "$key" "$val"
    # 매칭된 example 줄을 빈 placeholder ('# KEY=') 로 되돌려 값 제거.
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
    echo "env-load: ${key} moved — rotating the exposed key is recommended." >&2
}

# ============================================================================
# 2) confirm — 되돌릴 수 없는(상태 변경) 작업 전 명시적 동의
# ============================================================================
# (sudo reboot / apt purge / 드라이버 교체 같은 되돌릴 수 없는 작업은 사용자 동의 필요).
#
# 사용법:
#   confirm_or_abort "Reboot now? Unsaved work will be lost."
#
# 기본값: N. [yY] 만 진행. 비대화형 셸(TTY 없음)에서는 안전하게 중단.

confirm_or_abort() {
    local msg="$1"
    local reply=""

    # 비대화형 셸(CI / cron / systemd)에서는 기본 N — 사용자 결정 없이 절대 진행 안 함.
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

#######################################
# 같은 질문을 다시 묻고 싶지 않을 때 — 환경변수 ASSUME_YES=1 이면 자동 동의.
# CI / 자동화 래퍼가 동의를 명시적으로 표현하는 통로.
# Globals:
#   ASSUME_YES (읽기)
# Arguments:
#   $1 - 확인 메시지
#######################################
confirm_or_abort_assumable() {
    local msg="$1"
    if [[ "${ASSUME_YES:-0}" == "1" ]]; then
        echo "${msg} (auto-confirmed via ASSUME_YES=1)"
        return 0
    fi
    confirm_or_abort "$msg"
}

# ============================================================================
# 3) resume — step-6 reboot 를 넘어 설치를 자동 재개
# ============================================================================
# 일회성 GUI autostart 항목을 등록/제거 → reboot 후 install.sh 가 자동으로 이어지게 함.
# (OPENAI_API_KEY 는 더 이상 여기서 미리 안 받음 — install.sh 의 마지막 단계 openai-key-setup.sh 담당.)
#
# 동작 방식: GNOME autostart (.desktop) 가 로그인 시 터미널을 열어 install-resume-launcher.sh 실행
# → install.sh 재실행. install.sh 가 재개로 다시 진입하면 즉시 autostart 제거(일회성)
# — 그래야 로그인할 때마다 또 실행 안 됨.

RESUME_AUTOSTART_DIR="${HOME}/.config/autostart"
RESUME_AUTOSTART_FILE="${RESUME_AUTOSTART_DIR}/ros2-jazzy-install-resume.desktop"

#######################################
# reboot 후 자동 재개 등록: 로그인 시 터미널에서 install-resume-launcher.sh 를 실행.
# 터미널 에뮬레이터가 없으면 등록을 건너뛰고 수동 재실행을 안내.
# Globals:
#   RESUME_AUTOSTART_DIR, RESUME_AUTOSTART_FILE (읽기)
# Arguments:
#   $1 - 레포 루트 경로 (repo)
#######################################
register_resume_autostart() {
    local repo="$1"
    local launcher="${repo}/resources/install-resume-launcher.sh"
    local exec_line=""
    if command -v gnome-terminal >/dev/null; then
        exec_line="gnome-terminal -- bash \"${launcher}\""
    elif command -v x-terminal-emulator >/dev/null; then
        exec_line="x-terminal-emulator -e bash \"${launcher}\""
    else
        echo "[install] no terminal emulator — auto-resume not possible." >&2
        echo "             after reboot, run 'bash install.sh' manually." >&2
        return 0
    fi
    mkdir -p "${RESUME_AUTOSTART_DIR}"
    cat > "${RESUME_AUTOSTART_FILE}" <<EOF
[Desktop Entry]
Type=Application
Name=ros2_jazzy_test install resume
Comment=Auto-resume install.sh after a clean-install reboot (one-shot)
Exec=${exec_line}
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
    echo "[install] registered auto-resume after reboot: ${RESUME_AUTOSTART_FILE}" >&2
}

# autostart 항목을 제거 (멱등) — 재개 진입 시(일회성 보장)와 완료 시 호출됨.
remove_resume_autostart() {
    if [[ -f "${RESUME_AUTOSTART_FILE}" ]]; then
        rm -f "${RESUME_AUTOSTART_FILE}"
        echo "[install] removed auto-resume entry: ${RESUME_AUTOSTART_FILE}" >&2
    fi
    return 0
}

# ============================================================================
# 4) sudo-prime — sudo 비밀번호를 처음에 한 번만 받고, 이후 캐시를 살려 둠
# ============================================================================
# 사용법: sudo_prime [prefix]   # prefix 는 에러 줄의 라벨, 예: sudo_prime install / sudo_prime setup-app
#
# 왜 처음에 받나: 각 단계는 상세 출력(첫 `sudo` 프롬프트 포함)을 로그로 보내고 콘솔엔 살아있음을
# 알리는 heartbeat(작업 살아있음 신호)만 그림. 만약 비밀번호를 첫 단계 안에서 뒤늦게 받으면 그
# 프롬프트가 heartbeat 뒤에 가려져, 비밀번호를 다 입력하기도 전에 진행되는 것처럼 보임. 어떤
# 단계보다 먼저 이걸 부르면 프롬프트가 콘솔의 첫 화면이 됨 — 단계가 시작되기 전에 비밀번호를 입력.
#
# Keepalive: 60초마다 sudo 타임스탬프를 갱신해 긴 단계(드라이버 / colcon 빌드) 도중 다시 묻지 않게
# 함. 반드시 호출자(CALLER)의 셸 세션 안에 있어야 `sudo -n` 이 foreground 명령들과 같은 tty
# 타임스탬프(tty_tickets)를 갱신 — 분리된(setsid) 세션은 다른 티켓을 데워서 실제로는 살려 두지
# 못함. `( ) &` 서브셸 안의 `$$` 는 호출자 스크립트의 PID(bash) 이므로, 스크립트가 종료되면
# keepalive 도 스스로 종료됨.
sudo_prime() {
    local prefix="${1:-setup}"
    if ! sudo -v; then
        echo "${prefix}: cannot verify sudo privileges. Run as a sudo-capable regular user." >&2
        exit 1
    fi
    # 서브셸 안에서 set +e — 일시적인 sudo -n 실패나 sleep 인터럽트에 keepalive 가 조용히 죽지 않게.
    # 서브셸은 자신의 teardown 을 trap 으로 잡아 진행 중인 `sleep` 을 죽임: 안 그러면 아래 EXIT
    # trap 이 서브셸만 죽여서 `sleep` 자식이 호출자의 프로세스 그룹으로 고아가 됨 (넘겨받은 터미널
    # 에선 foreground 프로세스 그룹에 남아 입력을 막음).
    ( set +e
      trap 'kill "${_ka_sleep:-0}" 2>/dev/null; exit 0' TERM EXIT
      while kill -0 "$$" 2>/dev/null; do
          sudo -n true 2>/dev/null
          sleep 60 & _ka_sleep=$!
          wait "${_ka_sleep}"
      done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true' EXIT
}
