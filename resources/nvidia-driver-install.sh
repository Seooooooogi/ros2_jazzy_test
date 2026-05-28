#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/nvidia-driver-install.sh — NVIDIA GPU 드라이버 설치 (a01 step 1).
#
# 정책 (사용자 결정 2026-05-28):
#   - NVIDIA_DRIVER_VERSION 빈 값  → `ubuntu-drivers install` 로 noble 권장 드라이버 자동 선택
#     (RTX 4060 에서 ≈580). 추후 CUDA 메이저 (ADR-006) 최소 요구를 자동 만족.
#   - NVIDIA_DRIVER_VERSION 숫자   → 그 버전 force-pin 설치 (override, CI/특수 GPU 용).
#   설치 후 apt-mark hold 로 잠금 — `apt upgrade` 가 핀을 풀어 메이저를 올리는 drift 차단
#   (docs/COMPATIBILITY.md "drift 패턴" 참조).
#   reboot 는 여기서 하지 않음 — a01 의 마지막 step 이 confirm 후 처리.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

# 빌드 도구 + ubuntu-drivers (apt-get install 은 그 자체로 idempotent).
sudo apt-get update
sudo apt-get install -y build-essential gcc ubuntu-drivers-common dkms nvidia-modprobe

# 설치된 nvidia-driver-NNN 메타패키지명 해소. ubuntu-drivers 가 -open / -server
# 변형을 고를 수 있으므로 접미사 허용 (예: nvidia-driver-595-open).
# Status-Abbrev 2번째 글자가 'i' = 현재 설치됨. hold 된 패키지는 'hi' 라 'ii' 만
# 보면 놓친다 (이 스크립트가 직접 hold 를 걸므로 재실행 시 'hi' 가 됨) → '^.i' 로 매칭.
_resolve_driver_pkg() {
    dpkg-query -W -f='${db:Status-Abbrev}|${Package}\n' 'nvidia-driver-*' 2>/dev/null \
        | awk -F'|' '$1 ~ /^.i/ {print $2}' \
        | grep -E '^nvidia-driver-[0-9]+(-open|-server|-server-open)?$' | sort -V | tail -n1 || true
}

# 드라이버 설치: 이미 설치돼 있으면 생략(재실행 idempotency) / 핀 지정 시 그 버전 / 아니면 권장 자동.
driver_pkg="$(_resolve_driver_pkg)"
if [[ -n "${driver_pkg}" ]]; then
    echo "nvidia: 이미 설치됨 (${driver_pkg}) — 설치 단계 생략"
elif [[ -n "${NVIDIA_DRIVER_VERSION}" ]]; then
    echo "nvidia: force-pin nvidia-driver-${NVIDIA_DRIVER_VERSION}"
    sudo apt-get install -y "nvidia-driver-${NVIDIA_DRIVER_VERSION}"
    driver_pkg="$(_resolve_driver_pkg)"
else
    echo "nvidia: ubuntu-drivers install (noble 권장 드라이버 자동 선택)"
    sudo ubuntu-drivers install
    driver_pkg="$(_resolve_driver_pkg)"
fi

if [[ -z "${driver_pkg}" ]]; then
    echo "nvidia: 설치된 nvidia-driver-NNN 패키지를 찾지 못함" >&2
    exit 1
fi

# apt upgrade 가 핀을 풀지 못하도록 hold (이미 hold 면 skip — idempotent).
if apt-mark showhold | grep -qx "${driver_pkg}"; then
    echo "nvidia: ${driver_pkg} 이미 hold 됨"
else
    sudo apt-mark hold "${driver_pkg}"
fi

echo "nvidia: installed & held -> ${driver_pkg}"
echo "nvidia: 적용에는 재부팅 필요 (a01 마지막 step 에서 confirm 후 처리)."
