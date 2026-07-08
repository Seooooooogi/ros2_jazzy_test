#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/vscode-install.sh — Visual Studio Code 설치 (Microsoft apt 저장소).
#
# .deb 파일 한 번 내려받아 설치하는 대신 → Microsoft apt 저장소 + 키링(apt 서명 키) 으로 설치.
# 이후 apt 가 VS Code 업데이트까지 자동 관리.
# 저장소 = Ubuntu 코드네임 무관 stable main 채널 → Ubuntu 버전 바뀌어도 그대로 동작.
# 키링 = /etc/apt/keyrings/packages.microsoft.gpg 에 두고 signed-by 로 지정 (구식 apt-key 미사용).
# state 미변경 — 순수 설치 본문.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./apt-repo.sh
source "${SCRIPT_DIR}/apt-repo.sh"
config_assert_set

MS_KEY="${KEYRING_DIR}/packages.microsoft.gpg"
VSCODE_LIST=/etc/apt/sources.list.d/vscode.list

# 1) 사전 준비 도구 + 키링 디렉토리.
sudo apt-get update
sudo apt-get install -y wget gpg apt-transport-https ca-certificates
# 2) 키링 + apt 소스 추가 (add_apt_repo — armored 키를 dearmor(바이너리 GPG 키로 변환), 멱등).
arch="$(dpkg --print-architecture)"
add_apt_repo \
    --mode dearmor --downloader wget --key-write tee \
    --key-url "https://packages.microsoft.com/keys/microsoft.asc" --key-file "${MS_KEY}" \
    --list-file "${VSCODE_LIST}" \
    --list-line "deb [arch=${arch} signed-by=${MS_KEY}] https://packages.microsoft.com/repos/code stable main"

# 4) VS Code 설치 (원본은 설치 후 code GUI 를 자동 실행했는데, 비대화/원격 환경에선 멈춰서 제거함).
sudo apt-get install -y code

echo "vscode: success installing Visual Studio Code"
