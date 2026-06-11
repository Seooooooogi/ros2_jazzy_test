#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/vscode-install.sh — Visual Studio Code 설치 (Microsoft apt repo).
#
# 일회성 .deb 다운로드 대신 Microsoft apt repo + keyring 으로 apt 관리 설치 (자동 업데이트).
# repo 는 codename 무관(stable main) — Ubuntu 버전과 독립.
# keyring 은 /etc/apt/keyrings/packages.microsoft.gpg + signed-by (deprecated apt-key 미사용).
# 순수 설치 본문 — state 호출 없음.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./apt-repo.sh
source "${SCRIPT_DIR}/apt-repo.sh"
config_assert_set

MS_KEY="${KEYRING_DIR}/packages.microsoft.gpg"
VSCODE_LIST=/etc/apt/sources.list.d/vscode.list

# 1) 선행 도구 + keyring 디렉토리.
sudo apt-get update
sudo apt-get install -y wget gpg apt-transport-https ca-certificates
# 2) keyring + apt source (add_apt_repo — armored 키 dearmor, 멱등).
arch="$(dpkg --print-architecture)"
add_apt_repo \
    --mode dearmor --downloader wget --key-write tee \
    --key-url "https://packages.microsoft.com/keys/microsoft.asc" --key-file "${MS_KEY}" \
    --list-file "${VSCODE_LIST}" \
    --list-line "deb [arch=${arch} signed-by=${MS_KEY}] https://packages.microsoft.com/repos/code stable main"

# 4) VS Code 설치 (원본의 `code` GUI 자동 실행은 비대화형/원격에서 hang → 제거).
sudo apt-get install -y code

echo "vscode: success installing Visual Studio Code"
