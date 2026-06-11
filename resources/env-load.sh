#!/usr/bin/env bash
# resources/env-load.sh — Safe .env loader — 자격증명을 스크립트에 박지 않고 .env 에서 로드.
# source 전용 라이브러리 — set -euo 를 여기 두지 않는다(호출 진입점이 셸 옵션을 소유).
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/env-load.sh"
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
