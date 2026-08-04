#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/nvidia-container-toolkit-install.sh — NVIDIA Container Toolkit 설치.
#
# 이 toolkit = host 의 GPU 를 컨테이너 안에서 쓸 수 있게 열어 주는 runtime. 컨테이너 안 CUDA runtime =
# PyTorch wheel 에 이미 포함 → toolkit 의 역할 = host 의 driver 라이브러리와 /dev/nvidia* 장치를 컨테이너에 주입.
# docker-compose 의 deploy.resources.reservations.devices(nvidia)·`docker run --gpus` = 이 toolkit 과
# 등록된 nvidia runtime 있어야 동작 → 없으면 yolo 컨테이너가 GPU 못 잡고 기동 실패.
#
# 사전 준비: nvidia 드라이버(nvidia-driver-install.sh)·Docker(docker-install.sh) 먼저 설치돼 있어야 함.
# 컨테이너(yolo/voice)를 GPU 에서 돌리는 구성에서만 필요 — host 만 설치하는 경우엔 불필요.
#
# 키링(apt 서명 키) = /etc/apt/keyrings/nvidia-container-toolkit.gpg 에 배치(signed-by 방식 — deprecated 된 apt-key 미사용).
# 단독 실행: bash resources/nvidia-container-toolkit-install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# confirm_or_abort_assumable = lib.sh 소재(docker 재시작 동의 받는 함수).
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
config_assert_set

TOOLKIT_LIST=/etc/apt/sources.list.d/nvidia-container-toolkit.list
TOOLKIT_KEY="${KEYRING_DIR}/nvidia-container-toolkit.gpg"

# 0) 사전 조건 확인 — 드라이버·docker 없으면 크게 실패(fail-loud — 조용히 넘어가지 않고 바로 에러로 멈춰 반쪽 설치 방지).
#    SKIP_IF_NO_GPU=1 (install.sh 통합 흐름): GPU 없는 host 전용 머신 = toolkit 불필요 →
#    드라이버 없어도 에러 아닌 정상 skip 으로 취급(단계 = DONE 표시). 단독 실행 기본값 = fail-loud.
if ! command -v nvidia-smi >/dev/null 2>&1; then
    if [[ "${SKIP_IF_NO_GPU:-0}" == "1" ]]; then
        echo "nvidia-toolkit: no nvidia-smi — treating as a GPU-less host-only configuration and skipping."
        exit 0
    fi
    echo "nvidia-toolkit: no nvidia-smi — the nvidia driver must be installed first." >&2
    exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
    echo "nvidia-toolkit: no docker — docker must be installed first." >&2
    exit 1
fi

# 1) 사전에 필요한 도구.
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

# 2) 키링 + apt source 등록 (add_apt_repo — 원본 list 를 받아 signed-by 를 끼워 넣고, cat 으로 여러 줄 비교).
#    설치 직전 update 는 아래 3) 에서 하므로 여기선 --no-update.
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

# 4) docker runtime 등록 (멱등 — nvidia-ctk 가 /etc/docker/daemon.json 갱신).
sudo nvidia-ctk runtime configure --runtime=docker

# 5) runtime 적용 — daemon.json 변경 = docker 재시작 후에야 반영. 이미 적용돼 있으면 재시작 skip.
#    docker 데몬 재시작 = 되돌릴 수 없는 작업 → 명시적 동의 필요(ASSUME_YES=1 로 자동화 가능).
if docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
    echo "nvidia-toolkit: the nvidia runtime is already registered with docker (skipping restart)."
else
    confirm_or_abort_assumable "Restart the docker daemon to apply the nvidia runtime? (running containers will pause briefly)"
    sudo systemctl restart docker
fi

# 6) 검증 — runtime 이 등록됐는지 확인.
if ! docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then
    echo "nvidia-toolkit: warning — the nvidia runtime is not visible to docker. Check with 'docker info'." >&2
    exit 1
fi
echo "nvidia-toolkit: OK — docker nvidia runtime registered ->"
nvidia-ctk --version | head -1
