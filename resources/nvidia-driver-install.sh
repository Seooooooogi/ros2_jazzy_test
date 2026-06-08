#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/nvidia-driver-install.sh — NVIDIA GPU 드라이버 설치 (a01 step 2, 커널 베이스라인 다음).
#
# 정책:
#   - 기본: NVIDIA_DRIVER_VERSION + NVIDIA_DRIVER_FLAVOR 로 드라이버를 명시 핀 설치
#     (기본: nvidia-driver-595 closed). 자동선택은 머신/시점마다 다른 드라이버를 골라
#     비결정적이고, modules-extra 없는 반쪽 HWE 커널을 끌어와 재부팅 시 검은 화면을
#     유발했다 → 작업 머신의 검증된 구성을 결정적으로 재현하려 핀.
#   - HWE 커널-모듈 메타(linux-modules-nvidia-...-generic-hwe-24.04)를 함께 설치 →
#     커널 업데이트 시 매칭 nvidia 모듈을 자동으로 끌어와 동기 유지.
#   - 드라이버 userspace 는 apt-mark hold (apt upgrade 의 메이저 drift 차단). 커널/모듈
#     메타는 hold 하지 않는다 — hold 하면 커널 추적이 끊겨 다음 커널에서 모듈이 빠진다.
#   - NVIDIA_DRIVER_VERSION 빈값이면 ubuntu-drivers 자동선택으로 폴백 (override, 비결정성 감수).
#   - 재부팅 전 검증 게이트: 부팅 예정 커널에 nvidia 커널 모듈이 실제로 있는지 확인하고
#     없으면 exit 1 로 중단 — 검은 화면 brick 을 재부팅 전에 차단.
#   - reboot 는 여기서 하지 않음 — a01 의 reboot step 이 confirm 후 처리.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

# apt component 활성화 — nvidia-modprobe 는 multiverse 소속이라, 설치 변종(server/minimal)에서
# multiverse 가 꺼져 있으면 'unable to locate package nvidia-modprobe' 로 실패한다.
# software-properties-common 은 main 이라 항상 설치 가능, add-apt-repository 는 이미 활성이면
# no-op. (이 step 에 두는 이유: 재시도 resume 시에도 매번 보장 — kernel-baseline 이 DONE 으로
# skip 돼도 영향 없음.)
sudo apt-get update
sudo apt-get install -y software-properties-common
sudo add-apt-repository -y universe
sudo add-apt-repository -y multiverse

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

# 드라이버 설치: 이미 설치돼 있으면 생략(재실행 idempotency) / 핀 지정 시 그 버전+변형 / 아니면 폴백 자동.
driver_pkg="$(_resolve_driver_pkg)"
if [[ -n "${driver_pkg}" ]]; then
    echo "nvidia: 이미 설치됨 (${driver_pkg}) — 설치 단계 생략"
elif [[ -n "${NVIDIA_DRIVER_VERSION}" ]]; then
    # 핀 설치 (기본 경로): 드라이버 userspace + HWE 커널-모듈 메타를 함께.
    # 모듈 메타가 커널 업데이트 때 매칭 nvidia 모듈을 자동으로 끌어와 동기 유지한다.
    pin_pkg="nvidia-driver-${NVIDIA_DRIVER_VERSION}${NVIDIA_DRIVER_FLAVOR}"
    module_meta="linux-modules-nvidia-${NVIDIA_DRIVER_VERSION}${NVIDIA_DRIVER_FLAVOR}-${KERNEL_META#linux-}"
    echo "nvidia: 핀 설치 ${pin_pkg} (+ 커널-모듈 메타 ${module_meta})"
    sudo apt-get install -y "${pin_pkg}" "${module_meta}"
    driver_pkg="$(_resolve_driver_pkg)"
else
    echo "nvidia: NVIDIA_DRIVER_VERSION 미지정 — ubuntu-drivers 자동선택 폴백 (비결정적)" >&2
    echo "  경고: 폴백 경로는 커널-모듈 메타(linux-modules-nvidia-...-generic-hwe-24.04)를" >&2
    echo "  설치하지 않습니다. 다음 커널 업데이트 후 'dkms status' / nvidia 모듈 적재를 확인하세요." >&2
    sudo ubuntu-drivers install
    driver_pkg="$(_resolve_driver_pkg)"
fi

if [[ -z "${driver_pkg}" ]]; then
    echo "nvidia: 설치된 nvidia-driver-NNN 패키지를 찾지 못함" >&2
    exit 1
fi

# apt upgrade 가 핀을 풀지 못하도록 드라이버 userspace 만 hold (이미 hold 면 skip — idempotent).
# 커널-모듈 메타는 hold 하지 않는다: hold 하면 커널 업데이트 추적이 끊겨 다음 커널에서 nvidia 모듈이 빠진다.
if apt-mark showhold | grep -qx "${driver_pkg}"; then
    echo "nvidia: ${driver_pkg} 이미 hold 됨"
else
    sudo apt-mark hold "${driver_pkg}"
fi

echo "nvidia: installed & held -> ${driver_pkg}"

# --- 재부팅 전 검증 게이트 ---
# 부팅 예정 커널에 nvidia 커널 모듈이 실제로 존재하는지 확인.
# 재부팅 전에는 $(uname -r) 가 아직 구 커널일 수 있으므로 '실행 중 커널'이 아니라
# '부팅 예정 커널'을 본다. 모듈이 없으면 재부팅 시 디스플레이 드라이버 부재로 검은 화면이
# 되므로 여기서 중단한다 (silent brick → 재부팅 전 시끄러운 실패로 전환).
# 가정: GRUB 기본이 설치된 최신 커널 (Ubuntu 기본 GRUB_DEFAULT=0 + update-grub 정렬).
# grub-reboot 등으로 특정 이전 커널을 지정한 환경에서는 이 검사가 부정확할 수 있다.
# /lib/modules 에는 버전 디렉토리 외에 'kernel' 등 비-버전 항목이 있을 수 있으므로
# 버전 패턴(숫자로 시작)만 골라 최신을 고른다.
target_kernel="$(find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | grep -E '^[0-9]+\.' | sort -V | tail -n1)"
if find "/lib/modules/${target_kernel}" -name 'nvidia.ko*' 2>/dev/null | grep -q .; then
    echo "nvidia: 검증 OK — 부팅 예정 커널(${target_kernel})에 nvidia 커널 모듈 존재."
    echo "nvidia: 적용에는 재부팅 필요 (a01 의 reboot step 에서 confirm 후 처리)."
else
    echo "nvidia: 검증 실패 — 부팅 예정 커널(${target_kernel})에 nvidia.ko 부재." >&2
    echo "  지금 재부팅하면 검은 화면(디스플레이 드라이버 없음)이 될 수 있어 중단합니다." >&2
    echo "  점검: 'dkms status' / 'dpkg -l linux-modules-nvidia-*' / /var/log/apt/term.log" >&2
    exit 1
fi
