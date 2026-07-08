#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/realsense-install.sh — RealSense 설치(a02 그룹의 2·3 단계).
#
# 한 파일에 두 개의 subcommand 를 담지만, 각각을 별도 프로세스의 별도 단계로 실행
# (bash realsense-install.sh <sub>) — subcommand 마다 set -euo 진입점이 따로 있고, run_step 의 진행률/재개(resume) 키도 독립적.
#   sdk : librealsense2 SDK(DKMS 커널 모듈 + 유틸 + 헤더). apt repo·키링(apt 서명 키) 등록 포함.
#   ros : ROS2 realsense2 wrapper 패키지(camera + description). SDK 가 먼저 설치돼 있다고 가정.
#
# backup 의 a04-realsense01.sh / a05-realsense02.sh 를 jazzy/noble 로 옮긴 버전.
# 순수 설치 본문 — state 를 건드리는 호출 없음.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./apt-repo.sh
source "${SCRIPT_DIR}/apt-repo.sh"
config_assert_set

#######################################
# librealsense2 SDK(DKMS 커널 모듈 + 유틸 + 헤더) 설치. apt repo·키링 등록 포함.
# Globals:
#   KEYRING_DIR, KERNEL_HEADERS_META, UBUNTU_CODENAME (읽기)
# Outputs:
#   성공 시 요약 한 줄을 stdout 으로 출력.
#######################################
# 배경/이유:
#   - 2025-11 에 RealSense 가 Intel 에서 분사(spin-off)해 RealSense AI 가 되며 apt repo 도메인과 서명 키가 함께 바뀜.
#     옛 librealsense.intel.com/.../librealsense.pgp 는 2018 년 Intel 키(C8B3A55A...)를 주지만, noble repo 는
#     새 키(...FB0B24895113F120, @realsenseai.com)로 서명돼 있어 옛 키로는 검증 실패(NO_PUBKEY).
#     현재 공식 방법(librealsense/doc/distribution_linux.md) = realsenseai.com 도메인 + .asc(armored) 키를
#     gpg --dearmor 로 변환(dearmor = armored 텍스트 키를 바이너리 GPG 키로 변환).
#   - 키링은 ${KEYRING_DIR}/librealsenseai.gpg + signed-by 로 지정(deprecated 된 apt-key 미사용).
#   - repo codename 은 `lsb_release -cs` 대신 ${UBUNTU_CODENAME}(config 단일 소스) 사용.
#   - DKMS 커널 모듈 빌드에는 커널 헤더가 필요 → HWE 커널(Ubuntu 하드웨어 지원 커널) 헤더 메타(${KERNEL_HEADERS_META})와
#     현재 커널 헤더를 함께 설치. 메타가 있으면 커널 업데이트 뒤에도 헤더가 자동으로 따라와서 librealsense2-dkms
#     재빌드가 깨지지 않음(헤더가 없으면 카메라 커널 모듈 빌드 실패).
#   - 제거됨: `apt remove --purge libgtk-3-dev`(되돌릴 수 없는 purge, noble 에선 불필요),
#              `realsense-viewer` 자동 실행(GUI 가 떠서 진행이 막힘).
realsense_sdk() {
    local RS_KEY="${KEYRING_DIR}/librealsenseai.gpg"
    local RS_LIST=/etc/apt/sources.list.d/librealsenseai.list
    local RS_KEY_URL="https://librealsense.realsenseai.com/Debian/librealsenseai.asc"
    local RS_REPO="https://librealsense.realsenseai.com/Debian/apt-repo"

    # 0) 분사(spin-off) 이전 Intel 키/소스가 남아 있으면 제거 — apt-get update 전에 안 지우면
    #    옛 repo 의 NO_PUBKEY 때문에 첫 update 가 막힘. 이 파일은 이 프로젝트가 만든 산출물이라 다시 생성 가능.
    sudo rm -f /etc/apt/sources.list.d/librealsense.list "${KEYRING_DIR}/librealsense.pgp"

    # 1) 사전 도구 + 키링 디렉터리 + 커널 헤더(DKMS 빌드용 — HWE 커널 헤더 메타 + 현재 커널).
    sudo apt-get update
    sudo apt-get install -y curl ca-certificates gnupg apt-transport-https \
        "${KERNEL_HEADERS_META}" "linux-headers-$(uname -r)"
    # 2) 키링 + apt 소스(add_apt_repo — armored 키를 dearmor 변환, 멱등(여러 번 실행해도 결과 동일)).
    add_apt_repo \
        --mode dearmor --downloader curl-sSf --key-write tee \
        --key-url "${RS_KEY_URL}" --key-file "${RS_KEY}" \
        --list-file "${RS_LIST}" \
        --list-line "deb [signed-by=${RS_KEY}] ${RS_REPO} ${UBUNTU_CODENAME} main"

    # 4) librealsense2 SDK(커널 DKMS 모듈 + 유틸 + 헤더 + 디버그 심볼).
    sudo apt-get install -y \
        librealsense2-dkms \
        librealsense2-utils \
        librealsense2-dev \
        librealsense2-dbg

    echo "realsense-sdk: success installing RealSense librealsense2 SDK (${UBUNTU_CODENAME} apt repo)"
}

#######################################
# ROS2 realsense2 wrapper 패키지(camera + description) 설치. SDK 가 먼저 설치돼 있다고 가정.
# Globals:
#   ROS_DISTRO (읽기)
# Outputs:
#   성공 시 요약 한 줄을 stdout 으로 출력.
#######################################
# 배경/이유:
#   - ros-humble-realsense2-* → ros-${ROS_DISTRO}-realsense2-* 로 옮김.
#   - 원래의 glob(`ros-humble-realsense2-*`) 대신 패키지를 명시 — 설치 결과가 항상 같도록(deterministic).
#     camera 는 realsense2-camera-msgs 를 의존성으로 함께 끌어옴.
#   - rosdep init/update + colcon build 는 a02 의 colcon-build.sh 로 옮겨 중복 제거.
realsense_ros() {
    sudo apt-get update

    # ROS2 바이너리 패키지들은 하나의 동기화된 snapshot 을 이룸. 패키지 간 의존이 느슨하고(loose) SONAME 도
    # 안 올라가서, 서로 다른 snapshot 을 섞으면 dlopen 시점에 ABI 가 깨짐. 그러면 realsense2_camera 가
    # undefined symbol(diagnostic_updater::Updater::Updater(NodeBaseInterface, ... , double, uint8))로 죽음 —
    # 이미 깔린 diagnostic_updater 가 realsense2_camera snapshot 보다 오래된 경우. 의존이 느슨해서 apt 가
    # 이미 설치된 옛 diagnostic_updater 를 자동으로 올려주지 않기 때문. 그래서 먼저 설치된 ROS 패키지들을 현재
    # snapshot 으로 다시 맞춰(re-sync), realsense 가 요구하는 ABI 의존을 wrapper 가 빌드된 버전과 일치시킴.
    # 범위를 ros-${ROS_DISTRO}-* 네임스페이스로 일부러 한정: 여기서 전체 `apt upgrade` 는 피함(hold 로 잡아둔
    # docker/nvidia 핀(버전 고정)을 흔들기 때문). 그 패키지들은 이 glob 밖이고 어차피 hold 돼 있어 핀 안전(pin-safe).
    local ros_installed
    ros_installed="$(dpkg-query -W -f='${db:Status-Status} ${Package}\n' "ros-${ROS_DISTRO}-*" 2>/dev/null \
        | awk '$1 == "installed" { print $2 }' || true)"
    if [[ -n "${ros_installed}" ]]; then
        # shellcheck disable=SC2086  # 일부러 word-splitting 함: ros_installed 는 줄바꿈으로 구분된 패키지 목록
        sudo apt-get install -y --only-upgrade ${ros_installed}
    fi

    sudo apt-get install -y \
        "ros-${ROS_DISTRO}-realsense2-camera" \
        "ros-${ROS_DISTRO}-realsense2-description"

    echo "realsense-ros: success installing ROS2 ${ROS_DISTRO} realsense2 wrapper"
}

case "${1:?realsense-install: subcommand required (sdk|ros)}" in
    sdk) realsense_sdk ;;
    ros) realsense_ros ;;
    *) echo "realsense-install: unknown subcommand '$1' (sdk|ros)" >&2; exit 2 ;;
esac
