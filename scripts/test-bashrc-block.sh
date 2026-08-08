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

# 이 테스트는 bashrc_sync_block() 의 동작만 검증한다 — config.sh 의 기본값 해석에
# 결과가 좌우되면 안 된다. config.sh 는 몇몇 변수를 "${VAR:-default}" 형태로 두어
# 호출 셸의 환경변수가 이미 있으면 그 값을 그대로 쓴다(의도된 override 경로). 실행
# 셸이 이 변수들을 이미 export 하고 있으면(예: 다른 ROS 배포판을 쓰는 개인 셸)
# 테스트 결과가 그 환경에 따라 달라진다 — 실제로 RMW_IMPLEMENTATION 이 이 이유로
# 실패한 적이 있다. 여기서 명시적으로 고정해 어떤 셸에서 실행해도 결과가 같게 한다.
#
# RMW_IMPLEMENTATION 은 이후 config.sh 가 `=` 로 강제 고정하도록 바뀌어(레포 전체
# 측정이 CycloneDDS 전제) 아래 고정이 더는 hermeticity 에 필요하지 않다 — config.sh
# 를 source 하는 순간 이미 rmw_cyclonedds_cpp 로 확정된다. 그래도 지우지 않고 남겨
# 둔다: 이 값과 config.sh 의 강제값이 항상 같아야 한다는 사실 자체가 문서 역할을
# 하고, 혹시 나중에 config.sh 쪽이 다시 override 가능하게 바뀌면 이 줄이 없어야
# 비로소 테스트가 ambient 오염에 다시 노출된다(있으면 무해하게 안전망으로 남는다).
RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
DSR_WORKSPACE="${FAKEHOME}/cobot2_ws"
CYCLONEDDS_XML="${FAKEHOME}/.config/cyclonedds/cyclonedds.xml"

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

# 예전 방식이 만들어 놓은 상태를 그대로 재현한다(.11 실측 형태) + 관리 블록 밖에
# 사용자가 직접 써 놓은, 이 레포의 옛 형태와 접두사만 같고 값은 다른 줄들
# (삭제 패턴이 앵커 없이 접두사만 보면 이런 줄까지 지운다 — 리뷰에서 실측됨)
cat > "${FAKEHOME}/.bashrc" <<EOF
# 사용자가 직접 쓴 줄 — 반드시 살아남아야 한다
alias ll='ls -alF'
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp   # 다른 프로젝트용으로 직접 설정 — 값이 달라 지워지면 안 된다
export CYCLONEDDS_URI="file:///home/user/my-custom-cyclonedds.xml"   # 사용자 커스텀 설정 — 지워지면 안 된다
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
check_count "사용자 RMW(다른 값)" "export RMW_IMPLEMENTATION=rmw_fastrtps_cpp   # 다른 프로젝트용으로 직접 설정 — 값이 달라 지워지면 안 된다" 1
check_count "사용자 CYCLONEDDS_URI(다른 값)" 'export CYCLONEDDS_URI="file:///home/user/my-custom-cyclonedds.xml"   # 사용자 커스텀 설정 — 지워지면 안 된다' 1

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

echo "[7] symlink 로 관리되는 ~/.bashrc — symlink 는 그대로, 대상 파일만 갱신된다"
# dotfiles 도구(stow/chezmoi) 나 손으로 건 symlink 흉내. 새 mktemp 디렉토리를 쓰지
# 않고 FAKEHOME 하위에 만들어 기존 trap 하나로 계속 정리되게 한다.
DOTFILES_TARGET="${FAKEHOME}/dotfiles-bashrc"
SYMHOME="${FAKEHOME}/symlink-home"
mkdir -p "${SYMHOME}"
printf '# 사용자 dotfiles 저장소의 실제 bashrc\nalias gs="git status"\n' > "${DOTFILES_TARGET}"
ln -s "${DOTFILES_TARGET}" "${SYMHOME}/.bashrc"
before_inode="$(stat -c %i "${DOTFILES_TARGET}")"

HOME="${SYMHOME}" bashrc_sync_block

if [[ -L "${SYMHOME}/.bashrc" ]]; then
    echo "  PASS symlink 유지됨 (일반 파일로 안 바뀜)"
else
    echo "  FAIL symlink 이 사라지고 일반 파일로 바뀜" >&2
    fails=$((fails + 1))
fi

link_target="$(readlink "${SYMHOME}/.bashrc" 2>/dev/null || true)"
if [[ "${link_target}" == "${DOTFILES_TARGET}" ]]; then
    echo "  PASS symlink 대상 경로 불변 (${link_target})"
else
    echo "  FAIL symlink 대상이 바뀜 — now: '${link_target}' (기대 '${DOTFILES_TARGET}')" >&2
    fails=$((fails + 1))
fi

after_inode="$(stat -c %i "${DOTFILES_TARGET}" 2>/dev/null || echo MISSING)"
if [[ "${after_inode}" == "${before_inode}" ]]; then
    echo "  PASS 대상 파일 inode 불변 (${before_inode}) — sed -i 였다면 여기서 바뀐다"
else
    echo "  FAIL 대상 파일 inode 가 바뀜 — before=${before_inode} after=${after_inode}" >&2
    fails=$((fails + 1))
fi

if grep -qxF "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp" "${DOTFILES_TARGET}"; then
    echo "  PASS 대상 파일에 새 관리 블록 내용이 반영됨"
else
    echo "  FAIL 대상 파일에 새 관리 블록 내용이 반영되지 않음" >&2
    fails=$((fails + 1))
fi

if grep -qxF 'alias gs="git status"' "${DOTFILES_TARGET}"; then
    echo "  PASS 대상 파일의 기존 사용자 줄 보존"
else
    echo "  FAIL 대상 파일의 기존 사용자 줄이 사라짐" >&2
    fails=$((fails + 1))
fi

echo "[8] 끝 마커 없는 깨진 시작 마커 — 뒤에 온 사용자 줄은 살아남는다"
DANGLE_HOME="${FAKEHOME}/dangle-home"
mkdir -p "${DANGLE_HOME}"
cat > "${DANGLE_HOME}/.bashrc" <<'EOF'
# 시작 마커만 있고 끝 마커가 없는 깨진 상태(중단된 이전 실행 등으로 생길 수 있음)
# >>> ros2_jazzy_test env >>>
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
# 사용자가 마커 뒤에 직접 추가한 줄 — 반드시 살아남아야 한다
alias gd='git diff'
EOF

dangle_stderr="$(HOME="${DANGLE_HOME}" bashrc_sync_block 2>&1 >/dev/null)"

if grep -qxF "alias gd='git diff'" "${DANGLE_HOME}/.bashrc"; then
    echo "  PASS 깨진 마커 뒤 사용자 줄 생존"
else
    echo "  FAIL 깨진 마커 뒤 사용자 줄이 삭제됨(범위삭제가 파일 끝까지 먹었을 가능성)" >&2
    fails=$((fails + 1))
fi

dangle_begin_count="$(grep -cxF "# >>> ros2_jazzy_test env >>>" "${DANGLE_HOME}/.bashrc" || true)"
dangle_end_count="$(grep -cxF "# <<< ros2_jazzy_test env <<<" "${DANGLE_HOME}/.bashrc" || true)"
if [[ "${dangle_begin_count}" -eq 1 && "${dangle_end_count}" -eq 1 ]]; then
    echo "  PASS 재작성 후 마커 블록 정확히 한 쌍"
else
    echo "  FAIL 마커 블록 개수 이상 — begin=${dangle_begin_count} end=${dangle_end_count}" >&2
    fails=$((fails + 1))
fi

if [[ "${dangle_stderr}" == *"dds: warning"* ]]; then
    echo "  PASS 깨진 블록 발견 시 stderr 에 dds: 경고 출력"
else
    echo "  FAIL 깨진 블록 경고가 stderr 에 없음(got: '${dangle_stderr}')" >&2
    fails=$((fails + 1))
fi

echo "[9] config.sh 가 RMW_IMPLEMENTATION 을 강제 고정 — ambient 값과 무관하게 블록엔 cyclonedds 만 쓰인다"
# 이 스크립트 자신은 위쪽(35번째 줄)에서 RMW_IMPLEMENTATION 을 이미 고정해 놨으므로,
# 그 변수를 그대로 쓰면 config.sh 의 강제 여부와 무관하게 항상 통과해 버려 아무것도
# 증명하지 못한다. config.sh/lib.sh 를 새로 source 하는 별도 서브셸을 열어, 그
# 서브셸의 ambient 환경에만 RMW_IMPLEMENTATION=rmw_fastrtps_cpp 를 심어서 config.sh
# 자체가 그 값을 무시하는지를 직접 확인한다.
RULING_HOME="${FAKEHOME}/ruling-home"
mkdir -p "${RULING_HOME}"
RMW_IMPLEMENTATION=rmw_fastrtps_cpp HOME="${RULING_HOME}" bash -c '
    set -euo pipefail
    source "$1/resources/config.sh"
    source "$1/resources/lib.sh"
    bashrc_sync_block
' _ "${REPO_ROOT}"

if grep -qxF "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp" "${RULING_HOME}/.bashrc"; then
    echo "  PASS ambient rmw_fastrtps_cpp 를 무시하고 cyclonedds 로 기록"
else
    echo "  FAIL 블록에 cyclonedds 값이 없음 — config.sh 가 ambient 값을 강제하지 못하는 듯" >&2
    fails=$((fails + 1))
fi

if ! grep -qxF "export RMW_IMPLEMENTATION=rmw_fastrtps_cpp" "${RULING_HOME}/.bashrc"; then
    echo "  PASS ambient 값(rmw_fastrtps_cpp)이 블록에 새어 들어가지 않음"
else
    echo "  FAIL ambient 값이 그대로 블록에 기록됨" >&2
    fails=$((fails + 1))
fi

# 아래 4개 시나리오는 각각 독립된 가짜 HOME 에서, bashrc_sync_block 을 연달아
# 2회 호출한 뒤 두 번째 호출 결과로 수렴(convergence)을 확인한다 — "N회 호출해도
# 결과가 같다"는 이 함수 전체의 존재 이유이자, 개행 없는 파일 케이스가 실제로
# 깨뜨렸던 속성이다.

echo "[10] 관리 블록 밖의 사용자 CYCLONEDDS_URI(다른 값)는 2회 호출 후에도 살아남는다"
CUSTOM_URI_HOME="${FAKEHOME}/custom-uri-home"
mkdir -p "${CUSTOM_URI_HOME}"
cat > "${CUSTOM_URI_HOME}/.bashrc" <<'EOF'
export CYCLONEDDS_URI="file:///home/otheruser/custom/cyclonedds.xml"
alias keep='me'
EOF
HOME="${CUSTOM_URI_HOME}" bashrc_sync_block
HOME="${CUSTOM_URI_HOME}" bashrc_sync_block

custom_uri_count="$(grep -cxF 'export CYCLONEDDS_URI="file:///home/otheruser/custom/cyclonedds.xml"' "${CUSTOM_URI_HOME}/.bashrc" || true)"
if [[ "${custom_uri_count}" -eq 1 ]]; then
    echo "  PASS 사용자 CYCLONEDDS_URI(다른 값) 생존 (${custom_uri_count}회)"
else
    echo "  FAIL 사용자 CYCLONEDDS_URI(다른 값) — ${custom_uri_count}회 (기대 1회)" >&2
    fails=$((fails + 1))
fi

custom_uri_begin="$(grep -cxF "# >>> ros2_jazzy_test env >>>" "${CUSTOM_URI_HOME}/.bashrc" || true)"
custom_uri_end="$(grep -cxF "# <<< ros2_jazzy_test env <<<" "${CUSTOM_URI_HOME}/.bashrc" || true)"
if [[ "${custom_uri_begin}" -eq 1 && "${custom_uri_end}" -eq 1 ]]; then
    echo "  PASS 2회 호출 후 마커 블록 정확히 한 쌍(수렴)"
else
    echo "  FAIL 마커 블록 개수 이상 — begin=${custom_uri_begin} end=${custom_uri_end}" >&2
    fails=$((fails + 1))
fi

echo "[11] 끝 마커가 시작 마커보다 먼저 오는 뒤집힌 순서 — 사용자 줄 생존 + 경고"
REVERSED_HOME="${FAKEHOME}/reversed-home"
mkdir -p "${REVERSED_HOME}"
cat > "${REVERSED_HOME}/.bashrc" <<'EOF'
alias before='survives'
# <<< ros2_jazzy_test env <<<
alias middle='survives too'
# >>> ros2_jazzy_test env >>>
alias after='also survives'
EOF

reversed_stderr1="$(HOME="${REVERSED_HOME}" bashrc_sync_block 2>&1 >/dev/null)"
HOME="${REVERSED_HOME}" bashrc_sync_block

if grep -qxF "alias before='survives'" "${REVERSED_HOME}/.bashrc" \
    && grep -qxF "alias middle='survives too'" "${REVERSED_HOME}/.bashrc" \
    && grep -qxF "alias after='also survives'" "${REVERSED_HOME}/.bashrc"; then
    echo "  PASS 뒤집힌 마커 앞뒤 사용자 줄 전부 생존"
else
    echo "  FAIL 뒤집힌 마커 주변 사용자 줄 중 일부가 사라짐(범위삭제가 잘못 먹었을 가능성)" >&2
    fails=$((fails + 1))
fi

if [[ "${reversed_stderr1}" == *"dds: warning"* ]]; then
    echo "  PASS 뒤집힌 마커 발견 시 stderr 에 dds: 경고 출력"
else
    echo "  FAIL 뒤집힌 마커 경고가 stderr 에 없음(got: '${reversed_stderr1}')" >&2
    fails=$((fails + 1))
fi

reversed_begin="$(grep -cxF "# >>> ros2_jazzy_test env >>>" "${REVERSED_HOME}/.bashrc" || true)"
reversed_end="$(grep -cxF "# <<< ros2_jazzy_test env <<<" "${REVERSED_HOME}/.bashrc" || true)"
if [[ "${reversed_begin}" -eq 1 && "${reversed_end}" -eq 1 ]]; then
    echo "  PASS 2회 호출 후 마커 블록 정확히 한 쌍(수렴)"
else
    echo "  FAIL 마커 블록 개수 이상 — begin=${reversed_begin} end=${reversed_end}" >&2
    fails=$((fails + 1))
fi

echo "[12] 개행 없이 끝나는 ~/.bashrc — 2회 호출 후 마커가 중복되지 않는다"
NONEWLINE_HOME="${FAKEHOME}/nonewline-home"
mkdir -p "${NONEWLINE_HOME}"
printf "alias ll='ls -alF'\nalias no_newline_at_eof='true'" > "${NONEWLINE_HOME}/.bashrc"
if [[ "$(tail -c1 "${NONEWLINE_HOME}/.bashrc")" != "" ]]; then
    echo "  (fixture 확인: 마지막 바이트가 개행이 아님 — 의도한 상태)"
fi

HOME="${NONEWLINE_HOME}" bashrc_sync_block
HOME="${NONEWLINE_HOME}" bashrc_sync_block

nonewline_begin="$(grep -cxF "# >>> ros2_jazzy_test env >>>" "${NONEWLINE_HOME}/.bashrc" || true)"
nonewline_end="$(grep -cxF "# <<< ros2_jazzy_test env <<<" "${NONEWLINE_HOME}/.bashrc" || true)"
if [[ "${nonewline_begin}" -eq 1 && "${nonewline_end}" -eq 1 ]]; then
    echo "  PASS 2회 호출 후 마커 블록 정확히 한 쌍(수렴) — 이 태스크가 없애려던 중복 재발 안 함"
else
    echo "  FAIL 마커 블록 개수 이상 — begin=${nonewline_begin} end=${nonewline_end}" >&2
    fails=$((fails + 1))
fi

if grep -qxF "alias ll='ls -alF'" "${NONEWLINE_HOME}/.bashrc" \
    && grep -qxF "alias no_newline_at_eof='true'" "${NONEWLINE_HOME}/.bashrc"; then
    echo "  PASS 개행 없던 마지막 줄을 포함해 기존 사용자 줄 전부 생존"
else
    echo "  FAIL 개행 없이 끝나던 줄이 사라지거나 손상됨" >&2
    fails=$((fails + 1))
fi

echo "[13] 빈 ~/.bashrc — 2회 호출 후에도 깨끗한 블록 하나뿐이다"
EMPTY_HOME="${FAKEHOME}/empty-home"
mkdir -p "${EMPTY_HOME}"
: > "${EMPTY_HOME}/.bashrc"

HOME="${EMPTY_HOME}" bashrc_sync_block
HOME="${EMPTY_HOME}" bashrc_sync_block

empty_begin="$(grep -cxF "# >>> ros2_jazzy_test env >>>" "${EMPTY_HOME}/.bashrc" || true)"
empty_end="$(grep -cxF "# <<< ros2_jazzy_test env <<<" "${EMPTY_HOME}/.bashrc" || true)"
if [[ "${empty_begin}" -eq 1 && "${empty_end}" -eq 1 ]]; then
    echo "  PASS 2회 호출 후 마커 블록 정확히 한 쌍(수렴)"
else
    echo "  FAIL 마커 블록 개수 이상 — begin=${empty_begin} end=${empty_end}" >&2
    fails=$((fails + 1))
fi

empty_line_count="$(wc -l < "${EMPTY_HOME}/.bashrc")"
if [[ "${empty_line_count}" -eq 8 ]]; then
    echo "  PASS 블록 외에 다른 내용 없음 (총 ${empty_line_count}줄)"
else
    echo "  FAIL 블록 외에 다른 줄이 섞임 — 총 ${empty_line_count}줄 (기대 8줄)" >&2
    fails=$((fails + 1))
fi

if [[ "${fails}" -gt 0 ]]; then
    echo "FAILED: ${fails}건" >&2
    exit 1
fi
echo "test-bashrc-block: 전부 통과"
