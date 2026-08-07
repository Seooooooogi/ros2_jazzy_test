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
_state_ensure_file() {
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
Name=ros2_jazzy_test install resume
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

# ============================================================================
# 8) bashrc-sync · ~/.bashrc 관리 블록 재작성
# ============================================================================

# begin/end 마커 쌍으로 감싼 블록을 지운다. `sed 'begin,end d'`는 끝 마커를 못
# 찾으면 시작 마커부터 파일 끝까지 통째로 지운다 — 중단된 이전 실행이나 수동
# 편집으로 끝 마커만 빠진 상태가 되면, 그 뒤에 사용자가 써 놓은 줄까지 전부
# 사라진다. 끝 마커가 없으면 범위삭제 대신 시작 마커 줄만 지우고 경고한다.
_bashrc_delete_marker_block() {
    local begin="$1" end="$2" file="$3"
    if grep -qxF "${begin}" "${file}" && ! grep -qxF "${end}" "${file}"; then
        echo "dds: warning — bashrc marker '${begin}' has no matching end marker ('${end}'); the block looks corrupted (interrupted run or manual edit). Removing only the stray start marker, leaving the rest of the file untouched." >&2
        sed -i "\\@^${begin}\$@d" "${file}"
    else
        sed -i "\\@^${begin}\$@,\\@^${end}\$@d" "${file}"
    fi
}

# ~/.bashrc 의 이 레포 소유 영역을 마커 블록 하나로 재작성한다.
#
# 조건부 append(`grep || echo >>`)를 쓰지 않는 이유: 비교 문자열이 한 글자라도
# 어긋나면 가드가 통과해 같은 줄이 계속 쌓인다. 실제로 설치된 머신에서
# ROS setup source 가 2회씩 들어간 사례가 나왔다. 블록을 통째로 지우고 다시
# 쓰면 그런 어긋남 자체가 생기지 않는다.
#
# Globals: ROS_DISTRO, DSR_WORKSPACE, RMW_IMPLEMENTATION, CYCLONEDDS_XML, HOME
bashrc_sync_block() {
    local bashrc="${HOME}/.bashrc"
    local begin="# >>> ros2_jazzy_test env >>>"
    local end="# <<< ros2_jazzy_test env <<<"
    local tmp

    [[ -f "${bashrc}" ]] || touch "${bashrc}"

    # symlink 로 관리되는 ~/.bashrc(stow/chezmoi 같은 dotfiles 도구나 손으로 건
    # symlink)를 보존한다. `sed -i` 는 symlink 자리를 새 일반 파일로 갈아 치워
    # symlink 를 끊는다(원본 dotfiles 파일은 갱신되지 않음). 대신 임시 파일에서
    # 다 고친 뒤 `>` 리다이렉트로 원래 경로에 흘려 넣는다 — 그 경로가 symlink 면
    # 커널이 대상 파일을 열어 그 자리에 쓴다(symlink·inode 모두 유지).
    tmp="$(mktemp)"
    cp "${bashrc}" "${tmp}"

    # 1) 현재 마커 블록 제거
    _bashrc_delete_marker_block "${begin}" "${end}" "${tmp}"

    # 2) 예전 마커 블록 제거(이름이 두 종류였다)
    _bashrc_delete_marker_block \
        "# >>> ros2_jazzy_test cyclonedds env >>>" "# <<< ros2_jazzy_test cyclonedds env <<<" "${tmp}"
    _bashrc_delete_marker_block \
        "# >>> ros2_jazzy_test runtime env >>>" "# <<< ros2_jazzy_test runtime env <<<" "${tmp}"

    # 3) 예전 방식이 흩어 놓은 줄 제거.
    #    이 레포가 과거에 직접 써 넣은 형태만 정확히 일치할 때 지운다 —
    #    사용자가 손으로 쓴 다른 형태는 건드리지 않는다. 그래서 값 비교가
    #    필요한 줄은 양끝을 앵커링해 그 값까지 정확히 일치할 때만 지운다 —
    #    끝 앵커가 없으면 같은 접두사로 시작하되 값이 다른 사용자 줄까지
    #    같이 지워진다(실제로 그렇게 지워지는 걸 리뷰에서 확인함).
    sed -i \
        -e "\\@^source /opt/ros/${ROS_DISTRO}/setup.bash\$@d" \
        -e '\@^source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash$@d' \
        -e '\@^# export ROS_LOCALHOST_ONLY=1$@d' \
        -e '\@^export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp$@d' \
        -e '\@^export CYCLONEDDS_URI="file://.*/cyclonedds\.xml"$@d' \
        -e '\@^\[ -f \(~/.*install/setup\.bash\) \] && source \1$@d' \
        -e '\@^# \[테스트 2026-08-04\] config\.sh 제거 검증 — 원복은 이 줄의 주석 해제$@d' \
        -e '\@^# set -a; source ~/ros2_jazzy_test/resources/config.sh; set +a$@d' \
        -e '\@^# CycloneDDS standard + large-topic buffer/interface tuning (managed by hostcfg\.sh dds, do not edit manually)$@d' \
        "${tmp}"

    # 4) 블록 재작성
    {
        echo "${begin}"
        echo "# ROS2 환경 (관리 주체 = resources/hostcfg.sh · 직접 수정하지 말 것)"
        echo "source /opt/ros/${ROS_DISTRO}/setup.bash"
        echo "source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash"
        echo "[ -f ${DSR_WORKSPACE}/install/setup.bash ] && source ${DSR_WORKSPACE}/install/setup.bash"
        echo "export RMW_IMPLEMENTATION=${RMW_IMPLEMENTATION}"
        echo "export CYCLONEDDS_URI=\"file://${CYCLONEDDS_XML}\""
        echo "${end}"
    } >> "${tmp}"

    cat "${tmp}" > "${bashrc}"
    rm -f "${tmp}"
}
