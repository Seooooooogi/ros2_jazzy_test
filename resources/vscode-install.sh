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
config_assert_set

MS_KEY="${KEYRING_DIR}/packages.microsoft.gpg"
VSCODE_LIST=/etc/apt/sources.list.d/vscode.list

# 1) 선행 도구 + keyring 디렉토리.
sudo apt-get update
sudo apt-get install -y wget gpg apt-transport-https ca-certificates
sudo install -m 0755 -d "${KEYRING_DIR}"

# 2) Microsoft GPG 키 (armored → dearmor, 없을 때만 — idempotent).
if [[ ! -f "${MS_KEY}" ]]; then
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor | sudo tee "${MS_KEY}" >/dev/null
    sudo chmod a+r "${MS_KEY}"
fi

# 3) apt source (codename 무관 stable main; 동일 내용이면 재기록 안 함).
arch="$(dpkg --print-architecture)"
desired="deb [arch=${arch} signed-by=${MS_KEY}] https://packages.microsoft.com/repos/code stable main"
if ! { [[ -f "${VSCODE_LIST}" ]] && grep -qxF "${desired}" "${VSCODE_LIST}"; }; then
    echo "${desired}" | sudo tee "${VSCODE_LIST}" >/dev/null
fi
sudo apt-get update

# 4) VS Code 설치 (원본의 `code` GUI 자동 실행은 비대화형/원격에서 hang → 제거).
sudo apt-get install -y code

echo "success installing Visual Studio Code"
