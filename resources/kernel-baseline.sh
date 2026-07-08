#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/kernel-baseline.sh — HWE 커널(Ubuntu 하드웨어 지원 커널) 기반 보장 (a01 step 1, nvidia 이전).
#
# nvidia 드라이버와 RealSense(librealsense2-dkms)는 둘 다 커널에 묶여 동작하는 모듈.
# 커널 image 만 깔고 modules-extra(wifi / 일부 USB 입력 드라이버가 들어있음)가 빠지면,
# 부팅은 되지만 wifi/USB 키보드를 잃는 반쪽짜리 커널. 또 DKMS 모듈은 빌드하려면 커널
# headers 필요. 그래서 HWE meta + headers meta 를 명시적으로 설치해 image + headers +
# modules-extra 가 항상 함께 보장되고, 이후 커널 업데이트에서도 자동으로 따라오게 함.
# 순수 설치 본문 — state(진행 상태 기록) 호출 없음. 단계 표시(진행률·헤더)는 orchestrator 가 담당.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

# 1) HWE 커널 meta + headers meta 설치. --install-recommends 는 modules-extra 도 함께 끌어옴
#    (recommends 가 빠져 modules-extra 가 누락되는 것이 반쪽짜리 커널의 직접 원인).
#    apt-get install 은 이미 설치돼 있으면 아무것도 안 함 — 다시 실행해도 안전(멱등).
sudo apt-get update
sudo apt-get install -y --install-recommends "${KERNEL_META}" "${KERNEL_HEADERS_META}"

# 2) 지금 부팅된 커널에 대해 modules-extra / headers 를 명시적으로 보강. HWE meta 는 자기가
#    추적하는 커널만 보장하므로, 지금 부팅된 커널(설치 시점엔 GA(Ubuntu 기본 제공) 커널일 수 있음)은 따로 보강 필요.
#    apt-get install 은 이미 설치돼 있으면 아무것도 안 함 — 다시 실행해도 안전(멱등).
running="$(uname -r)"
sudo apt-get install -y "linux-modules-extra-${running}" "linux-headers-${running}"

# 3) 검증 — wifi 드라이버가 들어있는 net/wireless 모듈 디렉토리가 있는지 확인.
#    nvidia 게이트와 달리 여기서는 경고만 하고 종료하지 않음: HWE meta 가 방금 새 커널을 설치했다면,
#    지금 부팅돼 있는 옛 커널에는 wireless 디렉토리가 없는 게 정상일 수 있음(재부팅 후 새 커널에서 해결됨).
#    실제 차단(게이팅)은 재부팅 복귀 뒤 install.sh 의 초기 체크가 담당.
if [[ ! -d "/lib/modules/${running}/kernel/drivers/net/wireless" ]]; then
    echo "kernel-baseline: warning — /lib/modules/${running}/.../net/wireless missing." >&2
    echo "  the current kernel (${running}) may be missing modules-extra (affects wifi/USB input)." >&2
fi

echo "kernel-baseline: HWE kernel meta + headers + modules-extra guaranteed (current kernel ${running})."
