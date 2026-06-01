#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/realsense-sdk-install.sh — RealSense librealsense2 SDK (a02 step 2).
#
# backup a04-realsense01.sh 의 jazzy/noble 마이그레이션.
#   - RealSense 는 2025-11 Intel → RealSense AI 분사로 apt repo 도메인과 서명 키가 교체됨.
#     구 librealsense.intel.com/.../librealsense.pgp 는 2018 Intel 키(C8B3A55A...)를 서빙하지만
#     noble repo 는 신 키(...FB0B24895113F120, @realsenseai.com)로 서명 → 구 키로는 검증 실패
#     (NO_PUBKEY). 공식 현행 방식(librealsense/doc/distribution_linux.md) = realsenseai.com
#     도메인 + .asc(armored) 키를 gpg --dearmor 로 변환.
#   - keyring ${KEYRING_DIR}/librealsenseai.gpg + signed-by (deprecated apt-key 미사용).
#   - repo 코드네임 `lsb_release -cs` → ${UBUNTU_CODENAME} (config 단일 소스).
#   - DKMS 커널 모듈 빌드에 커널 헤더 필요 → HWE 헤더 메타(${KERNEL_HEADERS_META}) +
#     현재 커널 헤더 동반 설치. 메타가 있으면 커널 업데이트 후에도 헤더가 자동 추적돼
#     librealsense2-dkms 재빌드가 깨지지 않는다 (헤더 누락 = 카메라 커널 모듈 빌드 실패).
#   - 제거: `apt remove --purge libgtk-3-dev` (되돌릴 수 없는 purge / noble 불필요),
#           `realsense-viewer` 자동 실행 (GUI blocking).
# 순수 설치 본문 — state 호출 없음.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

RS_KEY="${KEYRING_DIR}/librealsenseai.gpg"
RS_LIST=/etc/apt/sources.list.d/librealsenseai.list
RS_KEY_URL="https://librealsense.realsenseai.com/Debian/librealsenseai.asc"
RS_REPO="https://librealsense.realsenseai.com/Debian/apt-repo"

# 0) 분사 전 구 Intel 키/소스 잔재 제거 (있으면) — apt-get update 전에 정리하지 않으면
#    구 repo 의 NO_PUBKEY 가 첫 update 를 막는다. 본 프로젝트가 만든 산출물이라 재생성 가능.
sudo rm -f /etc/apt/sources.list.d/librealsense.list "${KEYRING_DIR}/librealsense.pgp"

# 1) 선행 도구 + keyring 디렉토리 + 커널 헤더 (DKMS 빌드용 — HWE 헤더 메타 + 현재 커널).
sudo apt-get update
sudo apt-get install -y curl ca-certificates gnupg apt-transport-https \
    "${KERNEL_HEADERS_META}" "linux-headers-$(uname -r)"
sudo install -m 0755 -d "${KEYRING_DIR}"

# 2) RealSense AI GPG 키 (armored → dearmor, 없을 때만 — idempotent).
if [[ ! -f "${RS_KEY}" ]]; then
    curl -sSf "${RS_KEY_URL}" | gpg --dearmor | sudo tee "${RS_KEY}" >/dev/null
    sudo chmod a+r "${RS_KEY}"
fi

# 3) apt source (동일 내용이면 재기록 안 함 — 중복/덮어쓰기 방지).
desired="deb [signed-by=${RS_KEY}] ${RS_REPO} ${UBUNTU_CODENAME} main"
if ! { [[ -f "${RS_LIST}" ]] && grep -qxF "${desired}" "${RS_LIST}"; }; then
    echo "${desired}" | sudo tee "${RS_LIST}" >/dev/null
fi
sudo apt-get update

# 4) librealsense2 SDK (kernel DKMS 모듈 + 유틸 + 헤더 + 디버그 심볼).
sudo apt-get install -y \
    librealsense2-dkms \
    librealsense2-utils \
    librealsense2-dev \
    librealsense2-dbg

echo "success installing RealSense librealsense2 SDK (${UBUNTU_CODENAME} apt repo)"
