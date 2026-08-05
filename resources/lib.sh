#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck shell=bash
# resources/lib.sh · source 전용 라이브러리
#   단계 엔진 + 설치 UX 헬퍼 + apt 저장소 등록
#
# 함께 source 되는 일곱 그룹:
#   1) state        단계 상태(DONE/FAIL/SKIPPED/RUNNING)를 파일에 기록 → 끊긴 지점부터 재개
#   2) run_step     skip 판단 + 배너 + 로그 분리 + heartbeat 를 묶은 단계 실행 래퍼
#   3) steps        install.sh 가 부르는 단계 정의 + 전체 단계 수
#   4) confirm      비가역 작업(reboot / purge / 드라이버 교체) 전 명시적 동의
#   5) resume       재부팅 너머로 설치를 자동 재개하는 일회성 GUI autostart 등록/제거
#   6) sudo-prime   sudo 비밀번호 최초 1회 수령 + 캐시 유지
#   7) add_apt_repo apt 저장소·키링 등록(멱등)
#
# 선행 조건
#   config.sh 먼저 source(STATE_FILE / LOG_FILE / STATE_DIR / TOTAL_STEPS / KEYRING_DIR)
#   RESOURCE_DIR / STEPS_TOTAL = 호출자가 설정

# ============================================================================
# 1) state · 단계 진행 상태 추적(재개 가능한 재실행 + [n/total] 진행률)
# ============================================================================
# state 파일 형식 = 단계마다 `step_<name>=DONE|FAIL|SKIPPED|RUNNING` 한 줄(같은 단계 재기록 = 그 줄 교체 → 줄 수 불변)
#
# 사용법(설치 단계에서 호출):
#   step_should_skip a01_prerequirements && return 0
#   step_begin 1 6 a01_prerequirements
#   ... 작업 수행 ...
#   step_end DONE     # 실패 시엔 step_end FAIL

# 현재 실행 중인 단계 이름(step_begin -> step_end 짝 맞추기용)
__current_step=""

# STEP_STATE
#   1 = 단계 결과를 state 파일에 기록 + 완료 단계 skip (대상 install.sh: 재부팅 너머 재개 필요)
#   0 = 배너·로그·heartbeat 만, state 미변경(대상 setup-app.sh: 재개 개념 없음)
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
#   DONE(완료) 또는 SKIPPED(사용자가 일부러 제외) → 0
#   SKIPPED 인정 필요 이유: 재부팅 뒤 인자 없이 재실행해도 제외 단계가 부활하지 않게
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
    # STEP_STATE=0 → state 파일 생성·기록 모두 없음(setup-app.sh 전용 경로)
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

# 모든 단계 상태 출력(디버깅/검증용)
state_dump() {
    _state_ensure_file
    echo "--- state file: $STATE_FILE ---"
    cat "$STATE_FILE"
    echo "-------------------------------"
}

# ============================================================================
# 2) run_step · 단계 실행을 한곳에 모은 래퍼(오케스트레이션 정책)
# ============================================================================
# 진행률 분모 = 호출자가 설정한 STEPS_TOTAL, 없으면 config.sh 의 TOTAL_STEPS
#
# 출력 정책
#   기본 = 단계 명령의 stdout·stderr 모두 LOG_FILE 로만 → 콘솔 청결 유지
#   VERBOSE=1 = 콘솔 + 로그 양쪽에 tee
#   단계의 경고·에러도 로그에만 축적, 단 실패는 비공개 아님(step_end FAIL = [FAIL] 한 줄 + 로그 경로 출력)
# 실패 처리 = FAIL 기록 후 즉시 exit
#   → 호출자의 ERR trap 은 이 경로에서 미발동
#   ERR trap 담당 범위 = run_step 바깥의 명령 실패뿐

# 경과 시간 제자리 갱신 → 단계 진행 중 콘솔이 멈춘 것처럼 보이지 않게 함
# 사용 조건 = 출력이 로그로 가는 기본 모드 + 대화형 터미널(VERBOSE 모드 = 단계의 실제 출력이 콘솔로 흐름)
# 첫 출력 2초 지연 = 단계 초반의 sudo 비밀번호 프롬프트와 겹침 방지
_step_heartbeat() {
    local name="$1" start="$SECONDS" e
    while :; do
        sleep 2
        e=$(( SECONDS - start ))
        printf '\r  ⋯ %s running (%02d:%02d elapsed)\033[K' "$name" $(( e / 60 )) $(( e % 60 )) >&2
    done
}

# 한 단계 실행
#   완료된 단계 = skip
#   그 외 = 배너 → 실행 → 결과 기록
# --interactive = 단계가 사용자 입력을 받을 때 지정
#   heartbeat 의 제자리 갱신이 입력 프롬프트를 덮어씀 → 입력 깨짐
#   → 그 단계에서만 heartbeat off
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
    # 상세 설치 로그에 단계 구분 배너 추가(LOG_FILE 없는 환경 = STATE_DIR 로 대체)
    local log="${LOG_FILE:-${STATE_DIR:?run-step: STATE_DIR not set}/install.log}"
    mkdir -p "$(dirname "$log")"
    { echo; echo "===== [${n}/${total}] ${name} — $(date '+%F %T') ====="; } >>"$log"

    step_begin "${n}" "${total}" "${name}"

    # 출력 라우팅(기본 = 로그 전용 / VERBOSE=1 = 콘솔에도 tee)
    # tee = 비동기 → 명령 종료 후에도 버퍼 flush 진행 중일 수 있음
    #   대응: 전용 fd 로 열고 배너 출력 전에 close(EOF) → flush 완료까지 대기
    #   미대응 시 [OK]/[FAIL] 이 명령의 마지막 줄과 뒤섞임
    # sudo 프롬프트 = 어느 경로든 /dev/tty 행 → 삼켜지지 않음
    local rc=0 teepid="" tfd=-1 hbpid=""
    if [[ "${VERBOSE:-0}" == 1 ]]; then
        exec {tfd}> >(tee -a "$log" >&2); teepid=$!
        "$@" >&"$tfd" 2>&1 || rc=$?
        exec {tfd}>&-
        wait "$teepid" 2>/dev/null || true
    else
        if [[ -t 2 && "$interactive" -eq 0 ]]; then
            # 로그 경로 출력 없음(출력 시점 = 실패 시 + install.sh 맨 끝, 각 1회)
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

# 명령 미실행 + 단계를 SKIPPED 로 기록(사용자가 일부러 제외한 단계)
#   state 기록 필요 이유: 재부팅 뒤 이어서 실행할 때도 계속 skip
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
# 3) steps · 설치 단계 정의(install.sh 가 호출)
# ============================================================================
# 각 stage 함수 = offset 수령 → 단계 번호 = offset + 로컬 번호
#   install.sh: run_stage_a01 0 → reboot(6) → run_stage_a03 6 → dds(8) / network(9)
# state 키 = 번호 아님, 이름 → 번호가 밀려도 재개 호환성 유지
# reboot = 프로세스를 종료시킴 → run_step 의 일반 단계 틀에 부적합 → install.sh 가 직접 보유

# stage 별 단계 수(reboot 제외)
#   단계 추가 시 여기만 수정 → 전체 분모 자동 반영
STAGE_A01_COUNT=5
STAGE_A03_COUNT=1
INSTALL_EXTRA_COUNT=2   # 설치 전용: dds(8) / network(9)

# install.sh 전체 분모 = a01 5 + reboot 1 + a03 1 + extra 2 = 9
install_steps_total() {
    echo $(( STAGE_A01_COUNT + 1 + STAGE_A03_COUNT + INSTALL_EXTRA_COUNT ))
}

# a01: 커널 기준선 → NVIDIA → Docker → ROS2 desktop → ROS2 extras
#   서브커맨드마다 별도 프로세스의 별도 단계 → 한쪽 실패가 다른 쪽으로 전파되지 않음
#   skip_nvidia=1 = 드라이버 기설치로 간주 → 그 단계 skip(존재 여부 미확인)
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
# 사용법: confirm_or_abort "Reboot now? Unsaved work will be lost."
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

# 위와 같은 확인 + ASSUME_YES=1 이면 질문 없이 동의 처리(용도 = CI / 자동화가 동의를 표현하는 통로)
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
# GNOME autostart 항목(.desktop) = 로그인 시 터미널에서 install.sh --resume-terminal 실행
# 재개 진입 시 install.sh 가 그 항목 즉시 삭제(목적: 로그인할 때마다 재등장 방지)

RESUME_AUTOSTART_DIR="${HOME}/.config/autostart"
RESUME_AUTOSTART_FILE="${RESUME_AUTOSTART_DIR}/ros2-jazzy-install-resume.desktop"

# 재부팅 후 자동 재개 등록(터미널 에뮬레이터 부재 → 등록 생략 + 수동 재실행 안내)
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

# autostart 항목 제거 호출 시점 = 재개 진입 시(일회성 보장) + 설치 완료 시
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
# 사용법: sudo_prime [prefix]   # prefix 는 에러 줄의 라벨, 예: sudo_prime install / sudo_prime setup-app
#
# 모든 단계보다 먼저 호출하는 이유
#   단계 안에서 뒤늦게 질문 → 프롬프트가 heartbeat 줄에 가림
#   → 비밀번호 입력 완료 전에 설치가 진행되는 것처럼 보임
# keepalive = 60초마다 타임스탬프 갱신 → 긴 단계(드라이버 / colcon 빌드) 도중 재질문 방지
# 실행 위치 = 반드시 호출자의 셸 세션 안
#   같은 세션이라야 foreground 명령과 동일한 tty 티켓 갱신
#   분리된 세션 = 엉뚱한 티켓만 갱신 → 실제 유지 효과 없음
sudo_prime() {
    local prefix="${1:-setup}"
    if ! sudo -v; then
        echo "${prefix}: cannot verify sudo privileges. Run as a sudo-capable regular user." >&2
        exit 1
    fi
    # 서브셸 안 set +e (목적: 일시적 sudo -n 실패 / sleep 인터럽트에 keepalive 가 조용히 죽지 않게)
    # 서브셸이 자기 teardown 을 trap 으로 포착 → 진행 중인 sleep 까지 종료
    #   미처리 시 고아 sleep 이 터미널의 foreground 프로세스 그룹에 잔존 → 입력 차단
    ( set +e
      trap 'kill "${_ka_sleep:-0}" 2>/dev/null; exit 0' TERM EXIT
      # ( ) & 서브셸 안의 $$ = 이 서브셸 아님, 호출자 스크립트의 PID → 그 스크립트 종료 시 이 while 도 함께 종료
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
# 순서 = 키링 디렉터리 확보 → 키 부재 시에만 다운로드 → apt source list 기록 → (기본값) apt-get update
# 키 파일명 · signed-by 경로 · 키 처리 방식 = vendor 마다 상이 → 인자로 그대로 수령
#   임의 변경 → 그 저장소의 서명 검증 파손
#
# 사용법:
#   add_apt_repo \
#       --key-file PATH --key-url URL \
#       [--mode raw|dearmor] [--downloader curl|curl-sSf|wget] [--key-write tee|gpg-o] \
#       --list-file PATH \
#       { --list-line "deb ..." | --list-url URL --list-sed "s#..#..#g" } \
#       [--list-cmp grep|cat] [--no-update]
#
#   raw     = 받은 그대로 저장(armored .asc / 원본)
#   dearmor = armored 텍스트 키 → 바이너리 GPG 키로 변환 후 저장(--key-write 로 변환 명령 선택)
#   list-cmp grep = 한 줄만 비교(기본값) / cat = 여러 줄 전체 비교(upstream list 수령 시)

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

    # 키를 stdout 으로 내보내는 다운로더(vendor 가 쓰던 플래그 그대로 보존)
    local -a dl
    case "${downloader}" in
        curl)     dl=(curl -fsSL);;
        curl-sSf) dl=(curl -sSf);;
        wget)     dl=(wget -qO-);;
        *) echo "add_apt_repo: unknown downloader '${downloader}'" >&2; return 2;;
    esac

    # 1) 키링 디렉터리 + 키(다운로드 조건 = 키 부재 시에만 → N회 실행해도 결과 동일, 멱등)
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

    # 2) apt source list (내용 동일 → 재기록 없음, 중복 추가·덮어쓰기 방지)
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

    # 3) apt 캐시 갱신(직후 다른 update 가 이어지는 호출자 = --no-update 로 skip)
    if [[ "${do_update}" == "1" ]]; then
        sudo apt-get update
    fi
}

# 설치 실행마다 콘솔에 출력하는 저작권 배너(재부팅 후 자동 재개된 터미널에서도 출력)
print_copyright() {
    cat <<'EOF'
============================================================
 Cobot2 Jazzy Installer
 Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
============================================================
EOF
}
