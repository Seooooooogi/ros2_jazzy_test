#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# resources/install-resume-launcher.sh — 설치 중 재부팅(step 6) 뒤 GUI 자동시작이 부르는 1회용 재개 런처.
# 레포 위치에서 install.sh 재실행 + 끝난 뒤에도 터미널 열어 둠(결과를 눈으로 확인하려고).
# install.sh = 재개 시작 시점에 자동시작 등록 스스로 제거(1회용) → 로그인할 때마다 다시 안 뜸.
#
# set -e 미사용 — 명령 실패 시 스크립트 즉시 종료시키는 옵션인데, 설치 실패해도 결과 보여주려면 터미널이 열려 있어야 하기 때문.
# 대신 -u(정의 안 된 변수 쓰면 에러)와 pipefail(파이프 중간 단계 실패도 감지)은 켬 → 숨은 오류 드러냄.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
bash install.sh
rc=$?
echo
echo "[resume] install.sh exited (exit ${rc}). Keeping this terminal open so you can review the result."
# 대화형 셸로 넘기기 전에 터미널 입력 처리 상태(line discipline)를 정상 복구 —
# install.sh 의 단계 heartbeat(작업 살아있음 신호)나 sudo 비밀번호 입력창이 이 상태를 비정상으로 남겨둘 수 있음(이중 안전장치).
stty sane 2>/dev/null || true
exec bash
