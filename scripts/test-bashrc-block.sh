#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# scripts/test-bashrc-block.sh — bashrc_sync_block() 검증.
#
# 가짜 HOME 에서만 돈다(실제 ~/.bashrc 무변경). 검증 대상 세 가지:
#   1) N회 호출해도 각 줄이 정확히 1회 — 실측된 중복 재발 방지
#   2) 사용자가 직접 쓴 줄은 보존
#   3) 예전 방식이 남긴 흩어진 줄과 옛 마커 블록은 정리
#
# Usage: bash scripts/test-bashrc-block.sh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
FAKEHOME="$(mktemp -d)"
trap 'rm -rf "${FAKEHOME}"' EXIT
fails=0

# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=resources/config.sh
source "${REPO_ROOT}/resources/config.sh"
# shellcheck source=resources/lib.sh
source "${REPO_ROOT}/resources/lib.sh"

count_of() { grep -cxF "$1" "${FAKEHOME}/.bashrc" || true; }

check_count() {
    local label="$1" line="$2" want="$3" got
    got="$(count_of "${line}")"
    if [[ "${got}" -eq "${want}" ]]; then
        echo "  PASS ${label} (${got}회)"
    else
        echo "  FAIL ${label} — ${got}회 (기대 ${want}회)" >&2
        fails=$((fails + 1))
    fi
}

# 예전 방식이 만들어 놓은 상태를 그대로 재현한다(.11 실측 형태)
cat > "${FAKEHOME}/.bashrc" <<EOF
# 사용자가 직접 쓴 줄 — 반드시 살아남아야 한다
alias ll='ls -alF'
source /opt/ros/${ROS_DISTRO}/setup.bash
source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash
source /opt/ros/${ROS_DISTRO}/setup.bash
source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash
# export ROS_LOCALHOST_ONLY=1
# >>> ros2_jazzy_test runtime env >>>
[ -f ~/cobot2_ws/install/setup.bash ] && source ~/cobot2_ws/install/setup.bash
# [테스트 2026-08-04] config.sh 제거 검증 — 원복은 이 줄의 주석 해제
# <<< ros2_jazzy_test runtime env <<<
# >>> ros2_jazzy_test cyclonedds env >>>
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI="file:///old/path/cyclonedds.xml"
# <<< ros2_jazzy_test cyclonedds env <<<
EOF

echo "[1] 1회 호출 — 중복이 정리된다"
HOME="${FAKEHOME}" bashrc_sync_block
check_count "ROS setup source" "source /opt/ros/${ROS_DISTRO}/setup.bash" 1
check_count "colcon argcomplete" "source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash" 1
check_count "RMW" "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp" 1

echo "[2] 3회 더 호출해도 그대로다"
HOME="${FAKEHOME}" bashrc_sync_block
HOME="${FAKEHOME}" bashrc_sync_block
HOME="${FAKEHOME}" bashrc_sync_block
check_count "ROS setup source" "source /opt/ros/${ROS_DISTRO}/setup.bash" 1
check_count "colcon argcomplete" "source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash" 1
check_count "RMW" "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp" 1

echo "[3] 사용자 줄은 보존된다"
check_count "사용자 alias" "alias ll='ls -alF'" 1

echo "[4] 옛 마커 블록과 잔재는 사라진다"
check_count "옛 runtime 마커" "# >>> ros2_jazzy_test runtime env >>>" 0
check_count "옛 테스트 주석" "# [테스트 2026-08-04] config.sh 제거 검증 — 원복은 이 줄의 주석 해제" 0
check_count "옛 XML 경로" 'export CYCLONEDDS_URI="file:///old/path/cyclonedds.xml"' 0
check_count "옛 LOCALHOST 주석" "# export ROS_LOCALHOST_ONLY=1" 0

echo "[5] 마커 블록은 정확히 한 쌍이다"
check_count "블록 시작" "# >>> ros2_jazzy_test env >>>" 1
check_count "블록 끝" "# <<< ros2_jazzy_test env <<<" 1

echo "[6] bashrc 가 없어도 새로 만든다"
rm -f "${FAKEHOME}/.bashrc"
HOME="${FAKEHOME}" bashrc_sync_block
check_count "새 파일에도 RMW" "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp" 1

if [[ "${fails}" -gt 0 ]]; then
    echo "FAILED: ${fails}건" >&2
    exit 1
fi
echo "test-bashrc-block: 전부 통과"
