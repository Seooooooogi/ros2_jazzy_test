#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# resources/nvidia-container-toolkit-install.sh — NVIDIA Container Toolkit 설치.
#
# host GPU 를 컨테이너에 노출하는 런타임이다. 컨테이너 안 CUDA 런타임은 PyTorch wheel 이
# 번들하므로, toolkit 은 host 의 드라이버 라이브러리 + /dev/nvidia* 를 컨테이너에 주입하는 역할.
# docker-compose 의 deploy.resources.reservations.devices(nvidia) 와 `docker run --gpus` 가
# 이 toolkit + 등록된 nvidia 런타임에 의존한다 → 없으면 yolo 컨테이너가 GPU 로 못 뜬다.
#
# 전제: nvidia 드라이버(nvidia-driver-install.sh) + Docker(docker-install.sh) 설치 완료.
# 컨테이너(yolo/voice)가 GPU 로 동작해야 하는 구성에서만 필요 — host 설치만 하는 구성엔 불필요.
#
# keyring 은 /etc/apt/keyrings/nvidia-container-toolkit.gpg (signed-by — deprecated apt-key 미사용).
# 단독 실행: bash resources/nvidia-container-toolkit-install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# confirm_or_abort_assumable 는 interaction.sh 안 (docker 재시작 동의).
# shellcheck source=./interaction.sh
source "${SCRIPT_DIR}/interaction.sh"
# shellcheck source=./apt-repo.sh
source "${SCRIPT_DIR}/apt-repo.sh"
config_assert_set

TOOLKIT_LIST=/etc/apt/sources.list.d/nvidia-container-toolkit.list
TOOLKIT_KEY="${KEYRING_DIR}/nvidia-container-toolkit.gpg"

# 0) 전제 점검 — 드라이버 + docker 없으면 fail-loud (절반 설치 방지).
#    SKIP_IF_NO_GPU=1 (install.sh 통합 흐름): GPU 없는 host 전용 머신은 toolkit 이 불필요하므로
#    드라이버 부재를 에러가 아닌 정상 skip 으로 처리(step DONE 마킹). 단독 실행 기본은 fail-loud.
if ! command -v nvidia-smi >/dev/null 2>&1; then
    if [[ "${SKIP_IF_NO_GPU:-0}" == "1" ]]; then
        echo "nvidia-toolkit: nvidia-smi 없음 — GPU 없는 host 전용 구성으로 보고 skip."
        exit 0
    fi
    echo "nvidia-toolkit: nvidia-smi 없음 — nvidia 드라이버 설치 선행 필요." >&2
    exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
    echo "nvidia-toolkit: docker 없음 — docker 설치 선행 필요." >&2
    exit 1
fi

# 1) 선행 도구.
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

# 2) keyring + apt source (add_apt_repo — upstream list 받아 signed-by 주입, 다중행 cat 비교).
#    설치 전 update 는 아래 3) 이 하므로 --no-update.
add_apt_repo --no-update \
    --mode dearmor --downloader curl --key-write gpg-o \
    --key-url "https://nvidia.github.io/libnvidia-container/gpgkey" --key-file "${TOOLKIT_KEY}" \
    --list-file "${TOOLKIT_LIST}" \
    --list-url "https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list" \
    --list-sed "s#deb https://#deb [signed-by=${TOOLKIT_KEY}] https://#g" \
    --list-cmp cat

# 3) 설치.
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

# 4) docker 런타임 등록 (idempotent — nvidia-ctk 가 /etc/docker/daemon.json 갱신).
sudo nvidia-ctk runtime configure --runtime=docker

# 5) 런타임 적용 — daemon.json 변경은 docker 재시작 후 반영. 이미 떠 있으면 재시작 skip.
#    docker 데몬 재시작은 되돌릴 수 없는 작업이라 명시 동의(ASSUME_YES=1 로 자동화 가능).
if docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
    echo "nvidia-toolkit: docker 에 nvidia 런타임 이미 등록됨 (재시작 skip)."
else
    confirm_or_abort_assumable "docker 데몬을 재시작해 nvidia 런타임을 적용할까요? (실행 중 컨테이너가 잠깐 중단됩니다)"
    sudo systemctl restart docker
fi

# 6) 검증 — 런타임 등록 확인.
if ! docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
    echo "nvidia-toolkit: 경고 — nvidia 런타임이 docker 에 보이지 않습니다. 'docker info' 로 확인." >&2
    exit 1
fi
echo "nvidia-toolkit: OK — docker nvidia 런타임 등록 완료 ->"
nvidia-ctk --version | head -1
