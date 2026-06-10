#!/usr/bin/env bash
# resources/unattended.sh — 무인 설치(--unattended) 헬퍼.
# 시작 시 자격증명(OPENAI_API_KEY) 선수집 + reboot 후 GUI autostart 로 install.sh 자동 재개.
# install.sh 가 source 한다 — env-load.sh(_load_env/_require_env/_set_env_key) 선행 source 필요.
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
