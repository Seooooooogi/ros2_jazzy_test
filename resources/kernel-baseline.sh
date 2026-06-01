#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/kernel-baseline.sh — HWE 커널 베이스라인 보장 (a01 step 1, nvidia 이전).
#
# nvidia 드라이버와 RealSense(librealsense2-dkms)는 모두 커널에 결합된 모듈이다.
# 커널 이미지만 설치되고 modules-extra(wifi / 일부 USB 입력 드라이버 수록)가 빠지면
# 부팅은 되지만 wifi·USB 키보드가 사라지는 반쪽 커널이 된다. 또 DKMS 모듈은 커널 헤더가
# 있어야 빌드된다. HWE 메타 + 헤더 메타를 명시 설치해 이미지 + 헤더 + modules-extra 를
# 항상 함께 보장하고, 이후 커널 업데이트에서도 자동 추적되게 한다.
# 순수 설치 본문 — state 호출 없음 (오케스트레이터가 step 프레이밍을 소유).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
config_assert_set

# 1) HWE 커널 메타 + 헤더 메타. --install-recommends 로 modules-extra 까지 끌어온다
#    (recommends 누락 시 modules-extra 가 빠지는 것이 반쪽 커널의 직접 원인).
#    apt-get install 은 already-installed 면 no-op — 재실행 안전.
sudo apt-get update
sudo apt-get install -y --install-recommends "${KERNEL_META}" "${KERNEL_HEADERS_META}"

# 2) 현재 부팅 커널의 modules-extra / 헤더 명시 보강. HWE 메타는 메타가 추적하는 커널만
#    보장하므로, 지금 부팅된 커널(설치 시점 GA 일 수 있음)에는 별도 보강이 필요하다.
#    apt-get install 은 already-installed 면 no-op — 재실행 안전.
running="$(uname -r)"
sudo apt-get install -y "linux-modules-extra-${running}" "linux-headers-${running}"

# 3) 검증 — wifi 드라이버가 든 net/wireless 모듈 디렉토리 존재 확인.
#    nvidia 게이트와 달리 exit 하지 않고 경고만 한다: HWE 메타가 새 커널을 막 설치한
#    경우, 지금 부팅 중인 구 커널에 wireless 디렉토리가 없는 것이 정상일 수 있다(재부팅
#    후 새 커널에서 해소). 실제 차단은 재부팅 복귀 후 install.sh 의 조기 점검이 담당.
if [[ ! -d "/lib/modules/${running}/kernel/drivers/net/wireless" ]]; then
    echo "kernel-baseline: 경고 — /lib/modules/${running}/.../net/wireless 부재." >&2
    echo "  현재 커널(${running})에 modules-extra 가 누락됐을 수 있습니다 (wifi/USB 입력 영향)." >&2
fi

echo "kernel-baseline: HWE 커널 메타 + 헤더 + modules-extra 보장 완료 (현재 커널 ${running})."
