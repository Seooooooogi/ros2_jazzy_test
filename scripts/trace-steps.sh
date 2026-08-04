#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# scripts/trace-steps.sh — 설치 본문이 "실행했을 명령"을 스텁으로 가로채 파일로 남긴다.
# 리팩토링 전후 트레이스가 같으면 명령·순서·조건 분기를 안 건드렸다는 뜻이다.
#
# 사용법: bash scripts/trace-steps.sh <repo-dir> <out-dir>
#   예:   bash scripts/trace-steps.sh ~/ros2_jazzy_test .trace-baseline
#         bash scripts/trace-steps.sh ~/rjt-refactor   .trace-after
#         diff -ru .trace-baseline .trace-after
#
# set -e 를 켜지 않는다 — 스텁 환경에서 본문이 중간에 실패하는 것은 정상이고,
# 실패 지점이 전후로 같은지가 곧 검증 대상이다.
set -uo pipefail

REPO="$(cd "${1:?usage: trace-steps.sh <repo-dir> <out-dir>}" && pwd)"
OUT="${2:?usage: trace-steps.sh <repo-dir> <out-dir>}"
mkdir -p "${OUT}"

# 스텁·가짜 홈은 고정 경로를 쓴다. mktemp -d 로 만들면 실행마다 경로가 달라져
# 트레이스에 그 경로가 섞이고, 전후 비교가 전부 다르다고 나온다.
STUB=/tmp/trace-steps-stub
FAKEHOME=/tmp/trace-steps-home
rm -rf "${STUB}" "${FAKEHOME}"
mkdir -p "${STUB}" "${FAKEHOME}/cobot2_ws/src" "${FAKEHOME}/.config"
touch "${FAKEHOME}/.bashrc"

# 시스템을 바꾸는 명령을 전부 echo 로 갈아끼운다. 실제 실행이 없으니 몇 번을 돌려도 상태가 안 변한다.
# `cat >/dev/null` 로 먼저 stdin 을 다 비운다 — 본문이 `curl ... | gpg --dearmor | sudo tee ...` 처럼
# 스텁끼리 파이프로 잇는 경우, 읽는 쪽 스텁이 stdin 을 안 비우고 바로 종료하면 쓰는 쪽이 SIGPIPE(exit 141)로
# 죽는 레이스가 생겨 실행마다 결과가 달라진다. 항상 다 읽고 종료해야 파이프 양쪽이 결정적으로 끝난다.
for c in sudo apt-get apt-key add-apt-repository curl wget gpg nmcli rosdep colcon docker \
         systemctl usermod modprobe dkms update-initramfs pip pip3 snap tee git; do
    printf '#!/usr/bin/env bash\ncat >/dev/null\necho "CMD %s $*"\n' "${c}" > "${STUB}/${c}"
    chmod +x "${STUB}/${c}"
done

# 병합 후 레이아웃인지 병합 전 레이아웃인지는 새 파일 존재로 판별한다.
if [[ -f "${REPO}/resources/base-install.sh" ]]; then
    STEPS=(
        "kernel|base-install.sh kernel"
        "nvidia|base-install.sh nvidia"
        "docker|base-install.sh docker"
        "ros2_desktop|base-install.sh ros2-desktop"
        "ros2_extras|base-install.sh ros2-extras"
        "vscode|base-install.sh vscode"
        "dds|hostcfg.sh dds"
        "network|hostcfg.sh network"
        "dsr|app-install.sh dsr"
        "realsense_sdk|app-install.sh realsense-sdk"
        "realsense_ros|app-install.sh realsense-ros"
        "voice|app-install.sh voice"
        "colcon|app-install.sh colcon"
        "toolkit|app-install.sh toolkit"
    )
else
    STEPS=(
        "kernel|kernel-baseline.sh"
        "nvidia|nvidia-driver-install.sh"
        "docker|docker-install.sh"
        "ros2_desktop|ros2-packages.sh desktop"
        "ros2_extras|ros2-packages.sh extras"
        "vscode|vscode-install.sh"
        "dds|dds-tuning.sh"
        "network|network-static-ip.sh"
        "dsr|dsr-project-install.sh"
        "realsense_sdk|realsense-install.sh sdk"
        "realsense_ros|realsense-install.sh ros"
        "voice|voice-host-install.sh"
        "colcon|colcon-build.sh"
        "toolkit|nvidia-container-toolkit-install.sh"
    )
fi

for entry in "${STEPS[@]}"; do
    name="${entry%%|*}"
    cmd="${entry#*|}"
    rc=0
    # 레포 경로는 트레이스에 그대로 찍히므로 <REPO> 로 치환한다 — 두 worktree 경로가 다르기 때문.
    # stdin 은 /dev/null 로 고정 — 스텁의 `cat >/dev/null` 이 파이프가 아닌 단독 호출에서
    # 터미널 입력을 기다리며 멈추지 않게 한다(파이프로 이어지는 경우는 파이프 쪽 fd 를 그대로 씀).
    # shellcheck disable=SC2086
    ( cd "${REPO}" && PATH="${STUB}:${PATH}" HOME="${FAKEHOME}" \
        ASSUME_YES=1 SKIP_IF_NO_GPU=1 bash resources/${cmd} ) < /dev/null > "${OUT}/${name}.raw" 2>&1 || rc=$?
    sed -e "s#${REPO}#<REPO>#g" -e "s#${FAKEHOME}#<HOME>#g" -e "s#${STUB}#<STUB>#g" \
        "${OUT}/${name}.raw" > "${OUT}/${name}.trace"
    echo "exit=${rc}" >> "${OUT}/${name}.trace"
    rm -f "${OUT}/${name}.raw"
    echo "  traced ${name} (exit=${rc})"
done

# shellcheck disable=SC2012
echo "trace-steps: wrote $(ls -1 "${OUT}"/*.trace | wc -l) traces to ${OUT}"
