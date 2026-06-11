#!/usr/bin/env bash
# resources/confirm.sh — Confirm prompt for state-changing / irreversible operations
# (sudo reboot / apt purge / driver swap 등 되돌릴 수 없는 작업은 사용자 명시 동의 필수).
# source 전용 라이브러리 — set -euo 를 여기 두지 않는다(호출 진입점이 셸 옵션을 소유).
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/confirm.sh"
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
