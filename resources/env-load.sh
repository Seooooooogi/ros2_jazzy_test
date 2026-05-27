#!/usr/bin/env bash
# resources/env-load.sh — Safe .env loader (Hard Rule #10: no hardcoded secrets).
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
