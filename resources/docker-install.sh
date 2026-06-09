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
config_assert_set

DOCKER_LIST=/etc/apt/sources.list.d/docker.list
DOCKER_KEY="${KEYRING_DIR}/docker.asc"

# 1) 선행 도구.
sudo apt-get update
sudo apt-get install -y ca-certificates curl

# 2) GPG 키 (이미 있으면 skip — idempotent).
sudo install -m 0755 -d "${KEYRING_DIR}"
if [[ ! -f "${DOCKER_KEY}" ]]; then
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "${DOCKER_KEY}"
    sudo chmod a+r "${DOCKER_KEY}"
fi

# 3) apt source (동일 내용이면 재기록 안 함 — 중복/덮어쓰기 방지).
arch="$(dpkg --print-architecture)"
desired="deb [arch=${arch} signed-by=${DOCKER_KEY}] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable"
if ! { [[ -f "${DOCKER_LIST}" ]] && grep -qxF "${desired}" "${DOCKER_LIST}"; }; then
    echo "${desired}" | sudo tee "${DOCKER_LIST}" >/dev/null
fi

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

# 9) NVIDIA Container Toolkit — 컨테이너(yolo)가 host GPU 를 쓰려면 필요하다(compose 의 nvidia
#    device reservation / `docker run --gpus`). 없으면 yolo 컨테이너가 GPU 로 못 떠 compose up 이
#    실패한다. nvidia 드라이버(step2)+docker(여기) 선행 충족. 멱등.
#    nvidia-smi 가드: GPU 없는 host 전용 구성에선 toolkit 이 불필요하고 모듈이 fail-loud 하므로
#    드라이버가 있는 머신에서만 설치한다. 비대화 흐름이라 docker 재시작 동의를 자동 승인
#    (ASSUME_YES=1) — daemon.json 의 nvidia 런타임 등록을 즉시 반영(step6 reboot 전 검증 통과).
if command -v nvidia-smi >/dev/null 2>&1; then
    ASSUME_YES=1 bash "${SCRIPT_DIR}/nvidia-container-toolkit-install.sh"
else
    echo "docker: nvidia-smi 없음 — NVIDIA Container Toolkit 설치 skip (host 전용 구성)"
fi
