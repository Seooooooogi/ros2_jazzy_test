#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck shell=bash
# resources/lib.sh · source 전용 라이브러리
#   단계 엔진 + 설치 UX 헬퍼 + apt 저장소 등록
#   선행 조건 = config.sh 먼저 source / RESOURCE_DIR · STEPS_TOTAL = 호출자 설정

# ============================================================================
# 1) state · 단계 진행 상태 추적
# ============================================================================

# 현재 실행 중인 단계 이름
__current_step=""

# STEP_STATE · 1 = state 기록 + 완료 단계 skip / 0 = 배너·로그만
: "${STEP_STATE:=1}"

# state 파일 없으면 생성
# 레포 이름이 바뀌기 전(~/.ros2_jazzy_test)에 설치한 머신의 상태 디렉토리를 새 경로로 옮긴다.
# 안 옮기면 끝난 단계를 못 읽어 첫 단계부터 다시 깔린다(드라이버 재설치·재부팅 포함).
# 신규 경로가 이미 있으면 그쪽이 진실이므로 손대지 않는다 — 몇 번을 호출해도 결과가 같다.
_state_migrate_legacy() {
    local legacy="${STATE_DIR_LEGACY:-}" current="${STATE_DIR:-}"
    [[ -n "${legacy}" && -n "${current}" && "${legacy}" != "${current}" ]] || return 0
    [[ -d "${legacy}" && ! -e "${current}" ]] || return 0

    if mv "${legacy}" "${current}"; then
        echo "[install] moved install state: ${legacy} -> ${current} (repo renamed)" >&2
    else
        echo "[install] warning — could not move ${legacy} to ${current};" >&2
        echo "             install will restart from the first step." >&2
    fi
}

_state_ensure_file() {
    _state_migrate_legacy
    mkdir -p "$(dirname "$STATE_FILE")"
    [[ -f "$STATE_FILE" ]] || : > "$STATE_FILE"
}

# state 파일의 step_<이름> 줄 = 주어진 상태로 교체(없으면 추가)
_state_set() {
    local name="$1" status="$2" key
    _state_ensure_file
    key="step_${name}"
    if grep -qE "^${key}=" "$STATE_FILE"; then
        sed -i "s|^${key}=.*|${key}=${status}|" "$STATE_FILE"
    else
        echo "${key}=${status}" >> "$STATE_FILE"
    fi
}

# state 파일의 step_<이름> 현재 상태 출력(없으면 빈 문자열)
_state_get() {
    local name="$1"
    _state_ensure_file
    sed -n "s|^step_${name}=||p" "$STATE_FILE" | tail -n1
}

# 이 단계 skip 가능 여부 판정
step_should_skip() {
    local name="$1"
    _state_ensure_file
    grep -qE "^step_${name}=(DONE|SKIPPED)$" "$STATE_FILE"
}

# 단계 시작([n/total] 배너 출력 + state 에 RUNNING 기록)
step_begin() {
    local n="$1" total="$2" name="$3"
    __current_step="$name"
    echo
    echo "============================================================"
    echo "[${n}/${total}] step: ${name}"
    echo "============================================================"
    if [[ "${STEP_STATE}" == 1 ]]; then
        _state_ensure_file
        _state_set "${name}" RUNNING
    fi
}

# 현재 단계 종료 + state 에 결과 기록(status = DONE | FAIL | SKIPPED)
step_end() {
    local status="${1:-DONE}"
    if [[ -z "${__current_step}" ]]; then
        echo "state: step_end called without step_begin" >&2
        return 1
    fi
    [[ "${STEP_STATE}" == 1 ]] && _state_set "${__current_step}" "${status}"
    case "${status}" in
        DONE)    echo "[OK]  step ${__current_step} = DONE" ;;
        FAIL)    echo "[FAIL] step ${__current_step} = FAIL" >&2 ;;
        SKIPPED) echo "[SKIP] step ${__current_step} = SKIPPED" ;;
    esac
    __current_step=""
}

# 모든 단계 상태 출력
state_dump() {
    _state_ensure_file
    echo "--- state file: $STATE_FILE ---"
    cat "$STATE_FILE"
    echo "-------------------------------"
}

# ============================================================================
# 2) run_step · 단계 실행 래퍼
# ============================================================================

# 경과 시간 제자리 갱신 → 단계 진행 중 콘솔이 멈춘 것처럼 보이지 않게 함
_step_heartbeat() {
    local name="$1" start="$SECONDS" e
    while :; do
        sleep 2
        e=$(( SECONDS - start ))
        printf '\r  ⋯ %s running (%02d:%02d elapsed)\033[K' "$name" $(( e / 60 )) $(( e % 60 )) >&2
    done
}

# 한 단계 실행(완료 단계 skip / 그 외 = 배너 → 실행 → 결과 기록)
# --interactive = 입력 받는 단계에 지정(heartbeat off)
run_step() {
    local interactive=0
    if [[ "${1:-}" == --interactive ]]; then interactive=1; shift; fi
    local n="$1" name="$2"
    shift 2
    if [[ $# -eq 0 ]]; then
        echo "run-step: no command to run for '${name}' (run_step <n> <name> <cmd...>)." >&2
        exit 2
    fi
    local total="${STEPS_TOTAL:-${TOTAL_STEPS:?run-step: STEPS_TOTAL/TOTAL_STEPS not set}}"
    if [[ "${STEP_STATE}" == 1 ]] && step_should_skip "${name}"; then
        echo "[${n}/${total}] skip: ${name} (already $(_state_get "${name}" | tr '[:upper:]' '[:lower:]'))"
        return 0
    fi
# 상세 설치 로그에 단계 구분 배너 추가
    local log="${LOG_FILE:-${STATE_DIR:?run-step: STATE_DIR not set}/install.log}"
    mkdir -p "$(dirname "$log")"
    { echo; echo "===== [${n}/${total}] ${name} — $(date '+%F %T') ====="; } >>"$log"

    step_begin "${n}" "${total}" "${name}"

# 출력 라우팅(기본 = 로그 전용 / VERBOSE=1 = 콘솔에도 tee)
    local rc=0 teepid="" tfd=-1 hbpid=""
    if [[ "${VERBOSE:-0}" == 1 ]]; then
        exec {tfd}> >(tee -a "$log" >&2); teepid=$!
        "$@" >&"$tfd" 2>&1 || rc=$?
        exec {tfd}>&-
        wait "$teepid" 2>/dev/null || true
    else
        if [[ -t 2 && "$interactive" -eq 0 ]]; then
            _step_heartbeat "${name}" & hbpid=$!
        fi
        "$@" >>"$log" 2>&1 || rc=$?
        if [[ -n "$hbpid" ]]; then
            kill "$hbpid" 2>/dev/null || true
            wait "$hbpid" 2>/dev/null || true
            printf '\r\033[K' >&2   # 남은 heartbeat 줄 제거
        fi
    fi

    if [[ $rc -eq 0 ]]; then
        step_end DONE
    else
        step_end FAIL
        echo "  ↳ detailed log: ${log}" >&2
        exit 1
    fi
}

# 명령 미실행 + 단계를 SKIPPED 로 기록
run_step_skip() {
    local n="$1" name="$2" reason="${3:-}"
    local total="${STEPS_TOTAL:-${TOTAL_STEPS:?run-step-skip: STEPS_TOTAL/TOTAL_STEPS not set}}"
    if [[ "${STEP_STATE}" == 1 ]] && step_should_skip "${name}"; then
        echo "[${n}/${total}] skip: ${name} (already $(_state_get "${name}" | tr '[:upper:]' '[:lower:]'))"
        return 0
    fi
    echo "[${n}/${total}] skip: ${name}${reason:+ (${reason})}"
    if [[ "${STEP_STATE}" == 1 ]]; then
        _state_set "${name}" SKIPPED
    fi
}

# ============================================================================
# 3) steps · 설치 단계 정의
# ============================================================================

# stage 별 단계 수(reboot 제외)
STAGE_A01_COUNT=5
STAGE_A03_COUNT=1
INSTALL_EXTRA_COUNT=2   # 설치 전용: dds(8) / network(9)

# install.sh 전체 분모 = a01 5 + reboot 1 + a03 1 + extra 2 = 9
install_steps_total() {
    echo $(( STAGE_A01_COUNT + 1 + STAGE_A03_COUNT + INSTALL_EXTRA_COUNT ))
}

# a01: 커널 기준선 → NVIDIA → Docker → ROS2 desktop → ROS2 extras
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

# a03: VS Code · 재부팅 뒤에 도는 단계
run_stage_a03() {
    local off="$1"
    run_step $((off + 1)) a03_vscode bash "${RESOURCE_DIR}/base-install.sh" vscode
}

# ============================================================================
# 4) confirm · 비가역 작업 전 명시적 동의
# ============================================================================
# 기본값 = N / 진행 조건 = [yY] 만

confirm_or_abort() {
    local msg="$1"
    local reply=""

    # TTY 없는 셸(CI / cron / systemd) = 사용자 결정 없이 진행 금지
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

# 위와 같은 확인 + ASSUME_YES=1 이면 질문 없이 동의 처리
confirm_or_abort_assumable() {
    local msg="$1"
    if [[ "${ASSUME_YES:-0}" == "1" ]]; then
        echo "${msg} (auto-confirmed via ASSUME_YES=1)"
        return 0
    fi
    confirm_or_abort "$msg"
}

# ============================================================================
# 5) resume · 재부팅 너머로 설치 자동 재개
# ============================================================================

RESUME_AUTOSTART_DIR="${HOME}/.config/autostart"
RESUME_AUTOSTART_FILE="${RESUME_AUTOSTART_DIR}/ros2-jazzy-install-resume.desktop"

# 재부팅 후 자동 재개 등록
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
    mkdir -p "${RESUME_AUTOSTART_DIR}"
    cat > "${RESUME_AUTOSTART_FILE}" <<EOF
[Desktop Entry]
Type=Application
Name=cobot2_jazzy_installer install resume
Comment=Auto-resume install.sh after a clean-install reboot (one-shot)
Exec=${exec_line}
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
    echo "[install] registered auto-resume after reboot: ${RESUME_AUTOSTART_FILE}" >&2
}

# autostart 항목 제거
remove_resume_autostart() {
    if [[ -f "${RESUME_AUTOSTART_FILE}" ]]; then
        rm -f "${RESUME_AUTOSTART_FILE}"
        echo "[install] removed auto-resume entry: ${RESUME_AUTOSTART_FILE}" >&2
    fi
    return 0
}

# ============================================================================
# 6) sudo-prime · sudo 비밀번호 최초 1회 수령 + 이후 캐시 유지
# ============================================================================
sudo_prime() {
    local prefix="${1:-setup}"
    if ! sudo -v; then
        echo "${prefix}: cannot verify sudo privileges. Run as a sudo-capable regular user." >&2
        exit 1
    fi
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

# ============================================================================
# 7) add_apt_repo · apt 저장소·키링 등록(멱등)
# ============================================================================
# 사용법:
#   add_apt_repo \
#       --key-file PATH --key-url URL \
#       [--mode raw|dearmor] [--downloader curl|curl-sSf|wget] [--key-write tee|gpg-o] \
#       --list-file PATH \
#       { --list-line "deb ..." | --list-url URL --list-sed "s#..#..#g" } \
#       [--list-cmp grep|cat] [--no-update]

add_apt_repo() {
    local key_file="" key_url="" mode="raw" downloader="curl" key_write="tee"
    local list_file="" list_line="" list_url="" list_sed="" list_cmp="grep" do_update=1
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key-file)   key_file="$2";   shift 2;;
            --key-url)    key_url="$2";    shift 2;;
            --mode)       mode="$2";       shift 2;;
            --downloader) downloader="$2"; shift 2;;
            --key-write)  key_write="$2";  shift 2;;
            --list-file)  list_file="$2";  shift 2;;
            --list-line)  list_line="$2";  shift 2;;
            --list-url)   list_url="$2";   shift 2;;
            --list-sed)   list_sed="$2";   shift 2;;
            --list-cmp)   list_cmp="$2";   shift 2;;
            --no-update)  do_update=0;     shift;;
            *) echo "add_apt_repo: unknown argument '$1'" >&2; return 2;;
        esac
    done

# 키를 stdout 으로 내보내는 다운로더
    local -a dl
    case "${downloader}" in
        curl)     dl=(curl -fsSL);;
        curl-sSf) dl=(curl -sSf);;
        wget)     dl=(wget -qO-);;
        *) echo "add_apt_repo: unknown downloader '${downloader}'" >&2; return 2;;
    esac

# 1) 키링 디렉터리 + 키(키 부재 시에만 다운로드)
    sudo install -m 0755 -d "$(dirname "${key_file}")"
    if [[ ! -f "${key_file}" ]]; then
        case "${mode}" in
            raw)
                sudo curl -fsSL "${key_url}" -o "${key_file}"
                ;;
            dearmor)
                if [[ "${key_write}" == "gpg-o" ]]; then
                    "${dl[@]}" "${key_url}" | sudo gpg --dearmor -o "${key_file}"
                else
                    "${dl[@]}" "${key_url}" | gpg --dearmor | sudo tee "${key_file}" >/dev/null
                fi
                ;;
            *) echo "add_apt_repo: unknown mode '${mode}'" >&2; return 2;;
        esac
        sudo chmod a+r "${key_file}"
    fi

# 2) apt source list
    local desired
    if [[ -n "${list_url}" ]]; then
        # upstream 배포 list 수령 → signed-by 경로 삽입
        desired="$("${dl[@]}" "${list_url}" | sed "${list_sed}")"
    else
        desired="${list_line}"
    fi
    local need_write=1
    if [[ -f "${list_file}" ]]; then
        if [[ "${list_cmp}" == "cat" ]]; then
            [[ "$(cat "${list_file}")" == "${desired}" ]] && need_write=0
        else
            grep -qxF "${desired}" "${list_file}" && need_write=0
        fi
    fi
    if [[ "${need_write}" == "1" ]]; then
        echo "${desired}" | sudo tee "${list_file}" >/dev/null
    fi

# 3) apt 캐시 갱신
    if [[ "${do_update}" == "1" ]]; then
        sudo apt-get update
    fi
}

# 설치 실행마다 콘솔에 출력하는 저작권 배너
print_copyright() {
    cat <<'EOF'
============================================================
 Cobot2 Jazzy Installer
 Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
============================================================
EOF
}
