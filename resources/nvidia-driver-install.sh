#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/nvidia-driver-install.sh — NVIDIA GPU 드라이버 설치 (a01 두 번째 단계, 커널 기본 설정 뒤).
#
# 정책(Policy):
#   - 기본: NVIDIA_DRIVER_VERSION + NVIDIA_DRIVER_FLAVOR 로 드라이버 버전을 콕 집어(핀 고정) 설치
#     (기본값: nvidia-driver-595 closed). 자동 선택에 맡기면 머신·시점마다 다른 드라이버가 뽑혀
#     결과가 매번 달라짐(비결정적). 게다가 modules-extra 가 빠진 어중간한 HWE 커널(Ubuntu 하드웨어 지원 커널)로
#     끌려 들어와 재부팅 시 화면이 까맣게 죽음 → 검증된 작업용 머신 설정을 그대로 재현하려고 핀(버전 고정).
#   - HWE 커널 모듈 메타(linux-modules-nvidia-...-generic-hwe-24.04)도 함께 설치 →
#     커널이 업데이트되면 거기에 맞는 nvidia 모듈을 자동으로 끌어와 항상 짝이 맞음.
#   - 드라이버 유저스페이스만 apt-mark hold 로 고정(apt upgrade 로 크게 바뀌는 것 방지). 커널/모듈
#     메타는 hold 금지 — hold 하면 커널 추적이 끊겨 다음 커널에서 모듈이 빠짐.
#   - NVIDIA_DRIVER_VERSION 이 비어 있으면 ubuntu-drivers 자동 선택으로 넘어감(직접 override, 비결정성 감수).
#   - 재부팅 전 검증 게이트: 부팅될 커널에 nvidia 커널 모듈이 실제로 있는지 확인하고
#     없으면 exit 1 로 멈춤 — 재부팅 후 까만 화면으로 벽돌 되는 걸 미리 차단.
#   - 여기서는 재부팅 안 함 — a01 의 reboot 단계가 confirm 후 처리.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

# apt 컴포넌트 활성화 — nvidia-modprobe 는 multiverse 에 들어 있어서, multiverse 가 꺼진 설치본
# (server/minimal)에서는 'unable to locate package nvidia-modprobe' 로 실패.
# software-properties-common 은 main 에 있어 항상 설치 가능하고, add-apt-repository 는 이미 켜져 있으면 아무 일도 안 함(no-op).
# (이 단계에 둔 이유: 재시도·재개(resume)마다 다시 보장됨 — 커널 기본 설정 단계가 DONE 으로 skip 돼도 영향 없음.)
sudo apt-get update
sudo apt-get install -y software-properties-common
sudo add-apt-repository -y universe
sudo add-apt-repository -y multiverse

# 빌드 도구 + ubuntu-drivers (apt-get install 은 그 자체로 멱등 — 여러 번 실행해도 결과가 같음).
sudo apt-get update
sudo apt-get install -y build-essential gcc ubuntu-drivers-common dkms nvidia-modprobe

#######################################
# 설치된 nvidia-driver-NNN 메타 패키지 이름을 찾아 출력.
# ubuntu-drivers 가 -open / -server 변형을 고를 수 있어 접미사(예: nvidia-driver-595-open)까지 허용.
# dpkg 의 Status-Abbrev 두 번째 글자가 'i' 면 현재 설치됨. hold 된 패키지는 'hi' 라
# 'ii' 만 찾으면 놓침(이 스크립트가 스스로 hold 하므로 재실행 시 'hi' 로 보임) → '^.i' 로 매칭.
# Outputs:
#   찾은 패키지 이름을 stdout 으로. 없으면 빈 문자열.
#######################################
_resolve_driver_pkg() {
    dpkg-query -W -f='${db:Status-Abbrev}|${Package}\n' 'nvidia-driver-*' 2>/dev/null \
        | awk -F'|' '$1 ~ /^.i/ {print $2}' \
        | grep -E '^nvidia-driver-[0-9]+(-open|-server|-server-open)?$' | sort -V | tail -n1 || true
}

# 드라이버 설치: 이미 설치돼 있으면 skip(재실행 멱등) / 핀 지정돼 있으면 그 버전+플레이버 / 아니면 자동 선택으로 폴백.
driver_pkg="$(_resolve_driver_pkg)"
if [[ -n "${driver_pkg}" ]]; then
    echo "nvidia: already installed (${driver_pkg}) — skipping the install step"
elif [[ -n "${NVIDIA_DRIVER_VERSION}" ]]; then
    # 핀 설치(기본 경로): 드라이버 유저스페이스 + HWE 커널 모듈 메타를 함께 설치.
    # 커널이 업데이트되면 모듈 메타가 맞는 nvidia 모듈을 자동으로 끌어와 짝이 유지됨.
    pin_pkg="nvidia-driver-${NVIDIA_DRIVER_VERSION}${NVIDIA_DRIVER_FLAVOR}"
    module_meta="linux-modules-nvidia-${NVIDIA_DRIVER_VERSION}${NVIDIA_DRIVER_FLAVOR}-${KERNEL_META#linux-}"
    echo "nvidia: pin install ${pin_pkg} (+ kernel-module meta ${module_meta})"
    sudo apt-get install -y "${pin_pkg}" "${module_meta}"
    driver_pkg="$(_resolve_driver_pkg)"
else
    echo "nvidia: NVIDIA_DRIVER_VERSION unset — falling back to ubuntu-drivers auto-selection (non-deterministic)" >&2
    echo "  warning: the fallback path does not install the kernel-module meta (linux-modules-nvidia-...-generic-hwe-24.04)." >&2
    echo "  After the next kernel update, check 'dkms status' / nvidia module loading." >&2
    sudo ubuntu-drivers install
    driver_pkg="$(_resolve_driver_pkg)"
fi

if [[ -z "${driver_pkg}" ]]; then
    echo "nvidia: could not find an installed nvidia-driver-NNN package" >&2
    exit 1
fi

# 드라이버 유저스페이스만 hold 해서 apt upgrade 가 핀을 풀지 못하게 함(이미 hold 면 skip — 멱등).
# 커널 모듈 메타는 hold 금지: hold 하면 커널 업데이트 추적이 끊겨 다음 커널에서 nvidia 모듈이 빠짐.
if apt-mark showhold | grep -qx "${driver_pkg}"; then
    echo "nvidia: ${driver_pkg} already held"
else
    sudo apt-mark hold "${driver_pkg}"
fi

echo "nvidia: installed & held -> ${driver_pkg}"

# --- 재부팅 전 검증 게이트 ---
# 부팅될 커널에 nvidia 커널 모듈이 실제로 있는지 확인.
# 재부팅 전에는 $(uname -r) 이 아직 옛 커널일 수 있어서, '지금 돌고 있는 커널' 대신 '부팅될 커널'을 봄.
# 모듈이 없으면 재부팅 시 디스플레이 드라이버가 없어 화면이 까맣게 죽으므로, 여기서 멈춤
# (조용히 벽돌 되는 대신 재부팅 전에 크게 실패시킴).
# 가정: GRUB 기본 부팅 항목은 설치된 커널 중 가장 최신(Ubuntu 기본값 GRUB_DEFAULT=0 + update-grub 정렬 기준).
# grub-reboot 등으로 특정 옛 커널을 고정해 둔 환경에서는 이 확인이 부정확할 수 있음.
# /lib/modules 에는 버전 디렉토리 말고 'kernel' 같은 비-버전 항목도 섞여 있을 수 있어, 버전 패턴
# (숫자로 시작)만 골라 가장 최신을 취함.
target_kernel="$(find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | grep -E '^[0-9]+\.' | sort -V | tail -n1)"
if find "/lib/modules/${target_kernel}" -name 'nvidia.ko*' 2>/dev/null | grep -q .; then
    echo "nvidia: verification OK — the to-be-booted kernel (${target_kernel}) has the nvidia kernel module."
    echo "nvidia: applying requires a reboot (handled after a confirm in a01's reboot step)."
else
    echo "nvidia: verification failed — the to-be-booted kernel (${target_kernel}) lacks nvidia.ko." >&2
    echo "  Rebooting now could yield a black screen (no display driver), so we stop." >&2
    echo "  Check: 'dkms status' / 'dpkg -l linux-modules-nvidia-*' / /var/log/apt/term.log" >&2
    exit 1
fi
