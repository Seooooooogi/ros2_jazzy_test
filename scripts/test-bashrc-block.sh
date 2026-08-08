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

# 블록이 쓰는 형태 = 파일이 있을 때만 source 하는 가드형. hostcfg.sh 는 이미 설치된
# 호스트에서 단독 재실행할 수 있는데, ROS 나 colcon 이 없는 호스트에서 가드 없는
# source 는 셸을 열 때마다 오류를 뱉는다.
ROS_SETUP_LINE="[ -f /opt/ros/${ROS_DISTRO}/setup.bash ] && source /opt/ros/${ROS_DISTRO}/setup.bash"
COLCON_HOOK="/usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash"
COLCON_LINE="[ -f ${COLCON_HOOK} ] && source ${COLCON_HOOK}"

echo "[1] 1회 호출 — 중복이 정리된다"
HOME="${FAKEHOME}" bashrc_sync_block
check_count "ROS setup source" "${ROS_SETUP_LINE}" 1
check_count "colcon argcomplete" "${COLCON_LINE}" 1
check_count "RMW" "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp" 1
# 옛 방식이 흩어 놓은 가드 없는 줄은 정리 대상으로 남아 있어야 한다
check_count "옛 가드 없는 ROS source" "source /opt/ros/${ROS_DISTRO}/setup.bash" 0
check_count "옛 가드 없는 colcon hook" "source ${COLCON_HOOK}" 0

echo "[2] 3회 더 호출해도 그대로다"
HOME="${FAKEHOME}" bashrc_sync_block
HOME="${FAKEHOME}" bashrc_sync_block
HOME="${FAKEHOME}" bashrc_sync_block
check_count "ROS setup source" "${ROS_SETUP_LINE}" 1
check_count "colcon argcomplete" "${COLCON_LINE}" 1
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
if [[ "${empty_line_count}" -eq 10 ]]; then
    echo "  PASS 블록 외에 다른 내용 없음 (총 ${empty_line_count}줄)"
else
    echo "  FAIL 블록 외에 다른 줄이 섞임 — 총 ${empty_line_count}줄 (기대 10줄)" >&2
    fails=$((fails + 1))
fi

# 만들어진 .bashrc 를 실제 셸에서 source 해 보고, 그 셸에 남은 값을 돌려준다.
# 줄이 파일에 있는지가 아니라 셸이 최종적으로 무엇으로 해석하는지를 본다 —
# 줄은 멀쩡한데 효과가 뒤집히는 종류의 사고는 grep 으로는 보이지 않는다.
# 이 레포가 심어 놓은 값만 보이도록 관련 변수는 지운 환경에서 연다.
sourced_env_of() {
    local rc="$1"
    # 홑따옴표 유지 — $1·$? 는 이 셸이 아니라 새로 여는 셸이 풀어야 한다.
    # shellcheck disable=SC2016
    env -u CYCLONEDDS_URI -u CYCLONEDDS_XML -u RMW_IMPLEMENTATION \
        bash --noprofile --norc -c '
            source "$1" >/dev/null 2>&1
            printf "SOURCE_STATUS=[%s]\n" "$?"
            printf "CYCLONEDDS_URI=[%s]\n" "${CYCLONEDDS_URI-<unset>}"
            printf "RMW_IMPLEMENTATION=[%s]\n" "${RMW_IMPLEMENTATION-<unset>}"
        ' _ "${rc}"
}

assert_line() {
    local label="$1" haystack="$2" needle="$3"
    if [[ "${haystack}" == *"${needle}"* ]]; then
        echo "  PASS ${label}"
    else
        echo "  FAIL ${label} — '${needle}' 없음. 실제: $(printf '%s' "${haystack}" | tr '\n' ' ')" >&2
        fails=$((fails + 1))
    fi
}

echo "[14] XML 이 아직 없는 시점에 블록을 써도 ROS 가 멀쩡히 뜬다"
# 관리 블록은 ROS2 설치 단계에서 이미 쓰이는데 cyclonedds.xml 은 그보다 뒤(재부팅
# 이후 DDS 설정 단계)에 만들어진다. 그 사이에 새 셸을 열면 — 또는 사용자가 XML 을
# 지우면 — 없는 파일을 가리키는 CYCLONEDDS_URI 때문에 모든 ROS 노드가 기동에
# 실패한다("can't open configuration file ..." → rmw handle is invalid). 학생은
# 들어본 적도 없는 파일 이름을 보게 된다.
NOXML_HOME="${FAKEHOME}/no-xml-home"
mkdir -p "${NOXML_HOME}"
NOXML_XML="${NOXML_HOME}/.config/cyclonedds/cyclonedds.xml"
(
    CYCLONEDDS_XML="${NOXML_XML}"
    HOME="${NOXML_HOME}"
    bashrc_sync_block
)

noxml_out="$(sourced_env_of "${NOXML_HOME}/.bashrc")"
assert_line "XML 없으면 URI 도 없다"   "${noxml_out}" "CYCLONEDDS_URI=[<unset>]"
assert_line "source 종료 코드 0"       "${noxml_out}" "SOURCE_STATUS=[0]"
assert_line "ROS 통신 설정은 살아 있다" "${noxml_out}" "RMW_IMPLEMENTATION=[rmw_cyclonedds_cpp]"

echo "[15] XML 이 생긴 뒤에는 그 파일을 가리킨다"
mkdir -p "$(dirname "${NOXML_XML}")"
printf '<CycloneDDS/>\n' > "${NOXML_XML}"
(
    CYCLONEDDS_XML="${NOXML_XML}"
    HOME="${NOXML_HOME}"
    bashrc_sync_block
)

xml_out="$(sourced_env_of "${NOXML_HOME}/.bashrc")"
assert_line "URI 가 그 XML 을 가리킨다" "${xml_out}" "CYCLONEDDS_URI=[file://${NOXML_XML}]"
assert_line "source 종료 코드 0"        "${xml_out}" "SOURCE_STATUS=[0]"

# 두 경우를 관통하는 불변식: URI 가 있으면 그 파일이 반드시 존재해야 한다.
sourced_uri="$(printf '%s\n' "${xml_out}" | sed -n 's/^CYCLONEDDS_URI=\[file:\/\/\(.*\)\]$/\1/p')"
if [[ -n "${sourced_uri}" && -f "${sourced_uri}" ]]; then
    echo "  PASS URI 가 가리키는 파일이 실제로 존재"
else
    echo "  FAIL URI 가 없는 파일을 가리킴 — '${sourced_uri}'" >&2
    fails=$((fails + 1))
fi

line_no_of() { grep -nxF "$2" "$1" | head -1 | cut -d: -f1; }

check_order() {
    local label="$1" earlier="$2" later="$3"
    if [[ -n "${earlier}" && -n "${later}" && "${earlier}" -lt "${later}" ]]; then
        echo "  PASS ${label} (${earlier}번 줄 < ${later}번 줄)"
    else
        echo "  FAIL ${label} — 앞: '${earlier}' 뒤: '${later}'" >&2
        fails=$((fails + 1))
    fi
}

echo "[16] 블록 뒤에 붙인 사용자 override 는 재실행 후에도 효력을 유지한다"
# 설치기 설정을 덮어쓰는 가장 흔한 방법이 블록 뒤에 자기 줄을 덧붙이는 것이다.
# 블록을 원래 자리가 아니라 파일 끝에 다시 쓰면 그 줄은 파일에 그대로 남은 채
# 순서만 뒤집혀 효력을 잃는다 — 사용자는 자기 줄을 눈으로 보면서 왜 안 먹는지
# 설명할 방법이 없다. 줄이 지워지는 것보다 나쁘다.
OVERRIDE_HOME="${FAKEHOME}/override-home"
mkdir -p "${OVERRIDE_HOME}"
printf '%s\n' "alias top='mine'" > "${OVERRIDE_HOME}/.bashrc"
HOME="${OVERRIDE_HOME}" bashrc_sync_block   # 설치기가 블록을 만든 상태
{
    echo "export RMW_IMPLEMENTATION=rmw_fastrtps_cpp"
    echo "alias bottom='mine'"
} >> "${OVERRIDE_HOME}/.bashrc"

HOME="${OVERRIDE_HOME}" bashrc_sync_block   # 설치기 재실행

override_top="$(line_no_of "${OVERRIDE_HOME}/.bashrc" "alias top='mine'")"
override_begin="$(line_no_of "${OVERRIDE_HOME}/.bashrc" "# >>> ros2_jazzy_test env >>>")"
override_user="$(line_no_of "${OVERRIDE_HOME}/.bashrc" "export RMW_IMPLEMENTATION=rmw_fastrtps_cpp")"
override_bottom="$(line_no_of "${OVERRIDE_HOME}/.bashrc" "alias bottom='mine'")"

check_order "블록은 앞선 사용자 줄 뒤에 그대로 있다" "${override_top}" "${override_begin}"
check_order "블록은 뒤에 붙인 override 앞에 있다"    "${override_begin}" "${override_user}"
check_order "override 뒤 사용자 줄도 순서 유지"      "${override_user}" "${override_bottom}"

override_out="$(sourced_env_of "${OVERRIDE_HOME}/.bashrc")"
assert_line "셸이 해석한 최종값 = 사용자 override" "${override_out}" "RMW_IMPLEMENTATION=[rmw_fastrtps_cpp]"

echo "[17] 3번째 호출에도 자리와 최종값이 그대로다(수렴)"
HOME="${OVERRIDE_HOME}" bashrc_sync_block
again_begin="$(line_no_of "${OVERRIDE_HOME}/.bashrc" "# >>> ros2_jazzy_test env >>>")"
again_user="$(line_no_of "${OVERRIDE_HOME}/.bashrc" "export RMW_IMPLEMENTATION=rmw_fastrtps_cpp")"
check_order "블록이 여전히 override 앞" "${again_begin}" "${again_user}"
if [[ "${again_begin}" == "${override_begin}" ]]; then
    echo "  PASS 블록 시작 줄 번호 불변 (${again_begin})"
else
    echo "  FAIL 블록이 이동함 — ${override_begin} → ${again_begin}" >&2
    fails=$((fails + 1))
fi

echo "[18] 블록이 없던 파일에서는 끝에 붙인다"
APPEND_HOME="${FAKEHOME}/append-home"
mkdir -p "${APPEND_HOME}"
printf '%s\n' "alias only='mine'" > "${APPEND_HOME}/.bashrc"
HOME="${APPEND_HOME}" bashrc_sync_block
append_user="$(line_no_of "${APPEND_HOME}/.bashrc" "alias only='mine'")"
append_begin="$(line_no_of "${APPEND_HOME}/.bashrc" "# >>> ros2_jazzy_test env >>>")"
check_order "기존 줄 뒤에 블록이 붙는다" "${append_user}" "${append_begin}"

echo "[19] ROS 가 없는 호스트에서 새 셸을 열어도 오류가 나지 않는다"
# hostcfg.sh 는 설치된 호스트에서 단독 재실행할 수 있다고 문서화돼 있다. ROS 가
# 없는 호스트에 블록이 쓰이면, 가드 없는 source 는 셸을 열 때마다 오류를 뱉는다.
# 어느 머신에서 돌려도 같은 결과가 나오도록 없는 distro 를 일부러 지정한다.
NOROS_HOME="${FAKEHOME}/no-ros-home"
mkdir -p "${NOROS_HOME}"
(
    ROS_DISTRO="definitely-not-installed"
    HOME="${NOROS_HOME}"
    CYCLONEDDS_XML="${NOROS_HOME}/.config/cyclonedds/cyclonedds.xml"
    DSR_WORKSPACE="${NOROS_HOME}/cobot2_ws"
    bashrc_sync_block
)

# shellcheck disable=SC2016
noros_err="$(bash --noprofile --norc -c 'source "$1"' _ "${NOROS_HOME}/.bashrc" 2>&1 >/dev/null)"
if [[ -z "${noros_err}" ]]; then
    echo "  PASS 없는 경로를 source 하지 않아 오류 없음"
else
    echo "  FAIL 셸 시작 시 오류 발생 — ${noros_err}" >&2
    fails=$((fails + 1))
fi

if [[ "${fails}" -gt 0 ]]; then
    echo "FAILED: ${fails}건" >&2
    exit 1
fi
echo "test-bashrc-block: 전부 통과"
