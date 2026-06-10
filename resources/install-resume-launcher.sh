#!/usr/bin/env bash
# resources/install-resume-launcher.sh — 무인 설치 reboot 후 GUI autostart 가 호출하는 1회용 런처.
# install.sh --unattended 를 레포 위치에서 재기동하고, 종료 후 터미널을 열어 둔다(결과 확인용).
# install.sh 자신이 재개 진입 시 autostart 항목을 제거(one-shot)하므로 로그인마다 재발화하지 않는다.
#
# set -e 는 쓰지 않는다 — install 이 실패해도 터미널을 닫지 않고 결과를 보여줘야 한다.
# 단, -u(unbound var)·pipefail 은 적용해 잠재 오류를 드러낸다.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
bash install.sh --unattended
rc=$?
echo
echo "[resume] install.sh 종료 (exit ${rc}). 결과 확인용으로 이 터미널을 열어 둡니다."
exec bash
