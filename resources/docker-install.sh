#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/docker-install.sh — Docker CE 설치 (a01 step 2).
#
# 정책 (사용자 결정 2026-05-28):
#   - noble 용 latest stable docker-ce 스택 설치 (설치 시점 핀 없음).
#   - 설치 후 apt-mark hold 로 엔진 패키지 잠금 (apt upgrade drift 차단).
#   - 해소된 버전은 docs/COMPATIBILITY.md 에 기록 (스크립트가 끝에 echo).
#   keyring 은 /etc/apt/keyrings/docker.asc (signed-by — deprecated apt-key 미사용).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./apt-repo.sh
source "${SCRIPT_DIR}/apt-repo.sh"
config_assert_set

DOCKER_LIST=/etc/apt/sources.list.d/docker.list
DOCKER_KEY="${KEYRING_DIR}/docker.asc"

# 1) 선행 도구.
sudo apt-get update
sudo apt-get install -y ca-certificates curl

# 2) keyring + apt source (add_apt_repo — 멱등). 엔진 설치 전 update 는 아래 4) 가 하므로 --no-update.
arch="$(dpkg --print-architecture)"
add_apt_repo --no-update \
    --mode raw \
    --key-url "https://download.docker.com/linux/ubuntu/gpg" --key-file "${DOCKER_KEY}" \
    --list-file "${DOCKER_LIST}" \
    --list-line "deb [arch=${arch} signed-by=${DOCKER_KEY}] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable"

# 4) 엔진 설치 (latest stable, 핀 없음).
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 5) 엔진 패키지 hold (이미 hold 면 skip).
for pkg in docker-ce docker-ce-cli containerd.io; do
    if apt-mark showhold | grep -qx "${pkg}"; then
        echo "docker: ${pkg} 이미 hold 됨"
    else
        sudo apt-mark hold "${pkg}"
    fi
done

# 6) 현재 사용자를 docker 그룹에 (sudo 없이 실행). 적용은 재부팅/재로그인 후.
user="$(id -un)"
if id -nG "${user}" | tr ' ' '\n' | grep -qx docker; then
    echo "docker: ${user} 이미 docker 그룹"
else
    sudo usermod -aG docker "${user}"
    echo "docker: ${user} 를 docker 그룹에 추가 (적용은 재부팅/재로그인 후)"
fi

# 7) 검증 — 그룹 변경이 현재 셸엔 미적용이므로 sudo 로 실행. --rm 으로 컨테이너 정리.
sudo docker run --rm hello-world

# 8) 해소된 버전 기록용 출력 (COMPATIBILITY.md 갱신 시 참조).
echo "docker: installed & held ->"
docker --version
docker compose version

# NVIDIA Container Toolkit 는 여기서 설치하지 않는다 — docker-install 은 a01(step3)으로 reboot
# 이전이라 GPU 드라이버 커널 모듈이 아직 로드되지 않았고, 그 상태에서 toolkit 작업이 실패한다.
# reboot 이후 단계(install.sh step14)에서 nvidia-container-toolkit-install.sh 를 별도 실행한다.
