#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/docker-install.sh — Docker CE(도커 엔진) 설치 (a01 step 2).
#
# 정책 (사용자 결정 2026-05-28):
#   - noble(Ubuntu 24.04) 용 docker-ce 최신 stable 스택 설치 (설치 시점엔 버전 핀(고정) 안 함).
#   - 설치 후 엔진 패키지를 apt-mark hold — apt upgrade 때 버전 자동 밀림 방지.
#   - 확정된 버전 = docs/COMPATIBILITY.md 에 기록 (스크립트가 맨 끝에서 출력).
#   키링(apt 서명 키) = /etc/apt/keyrings/docker.asc (signed-by 방식 — deprecated 된 apt-key 미사용).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
config_assert_set

DOCKER_LIST=/etc/apt/sources.list.d/docker.list
DOCKER_KEY="${KEYRING_DIR}/docker.asc"

# 1) 사전 준비 도구(ca-certificates, curl) 설치.
sudo apt-get update
sudo apt-get install -y ca-certificates curl

# 2) 키링 + apt 소스 등록 (add_apt_repo — 멱등: 여러 번 실행해도 결과 동일). 엔진 설치 직전 apt update = 아래 4) 에서 → 여기선 --no-update.
arch="$(dpkg --print-architecture)"
add_apt_repo --no-update \
    --mode raw \
    --key-url "https://download.docker.com/linux/ubuntu/gpg" --key-file "${DOCKER_KEY}" \
    --list-file "${DOCKER_LIST}" \
    --list-line "deb [arch=${arch} signed-by=${DOCKER_KEY}] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable"

# 4) 엔진 설치 (최신 stable, 버전 핀(고정) 안 함). 멱등: docker-ce 가 이미 깔려 있으면 건너뜀.
#    5) 의 hold 가 버전 밀림 방지 → 다시 실행해도 업그레이드 발생 금지. hold 된 엔진 패키지에
#    대해 repo 에 더 새로운 후보 버전이 있는 상태에서 `apt-get install` 을 또 돌리면 곧바로 에러 발생:
#      "E: Held packages were changed and -y was used without --allow-change-held-packages".
#    정책 = 최신 버전을 한 번만 설치하고 hold — install.sh 를 다시 돌려도(예: --reset 후) hold 된 버전 그대로 유지.
#    (--allow-change-held-packages 를 붙이면 매 재실행마다 docker 를 업그레이드해서 에러를 "해결"해 버림 → hold 로 버전 고정한 의미 소멸.)
sudo apt-get update
if dpkg-query -W -f='${Status}' docker-ce 2>/dev/null | grep -q 'ok installed'; then
    echo "docker: docker-ce already installed — skipping the engine install (hold blocks drift)"
else
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# 5) 엔진 패키지를 hold(버전 고정) — 이미 hold 돼 있으면 건너뜀.
for pkg in docker-ce docker-ce-cli containerd.io; do
    if apt-mark showhold | grep -qx "${pkg}"; then
        echo "docker: ${pkg} already held"
    else
        sudo apt-mark hold "${pkg}"
    fi
done

# 6) 현재 사용자를 docker 그룹에 추가 (sudo 없이 docker 를 쓸 수 있게). 실제 반영은 재부팅/재로그인 후.
user="$(id -un)"
if id -nG "${user}" | tr ' ' '\n' | grep -qx docker; then
    echo "docker: ${user} already in the docker group"
else
    sudo usermod -aG docker "${user}"
    echo "docker: added ${user} to the docker group (applied after reboot/re-login)"
fi

# 7) 검증 — 그룹 변경이 지금 이 셸엔 아직 미반영 → sudo 로 실행. --rm = 실행 끝난 컨테이너 삭제.
sudo docker run --rm hello-world

# 8) 확정된 버전을 기록용으로 출력 (COMPATIBILITY.md 갱신할 때 참고).
echo "docker: installed & held ->"
docker --version
docker compose version

# NVIDIA Container Toolkit(GPU 를 컨테이너 안에서 쓰게 해 주는 도구)은 여기서 미설치 — docker-install 은 a01(step3),
# 즉 재부팅 전 단계라 GPU 드라이버 커널 모듈 아직 미로드 → 그 상태에서 툴킷 작업 시 실패.
# 이 작업 = 재부팅 이후 단계에서 nvidia-container-toolkit-install.sh 가 따로 실행(install.sh step14).
