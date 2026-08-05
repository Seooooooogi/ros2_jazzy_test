#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# containers/build-all.sh · yolo 앱 컨테이너 이미지 빌드 + 검증 게이트
#
# host 설치와 독립 동작(Docker 엔진만 필요)
# voice = 컨테이너 아님, host 실행(app-install.sh voice) → 여기서 미빌드 → 빌드 대상 = yolo 이미지 하나뿐
# 빌드 대상 스테이지 = yolo 이미지의 `builder`
#   :dev-builder 태그 = 소스를 live-mount 하는 dev 이미지
#   실행 = bringup / docker-compose.dev.yml
# "격리 검증(isolated verification)" 항목
#   (1) 이미지 빌드 성공
#   (2) secret 위생 = docker history 에 자격증명 흔적 없음
#   (3) 컨테이너 안 import smoke = 가벼운 import 확인
# 이 단계 요구사항 = GPU / 카메라 / 모델 가중치 불필요(모듈 import 만 확인)
# 미검증 항목 = torch.cuda.is_available() / 서비스 왕복(round-trip) / od_msg 해시 일치 → host e2e 이후 단계 소관
#
# 호출자 = setup-app.sh 의 컨테이너 단계(빌드 + 검증)
# 단독 실행도 가능
# Usage: bash containers/build-all.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=resources/config.sh
source "${REPO_ROOT}/resources/config.sh"

# 이미지 좌표(image coordinates)
#   DOCKERHUB_USER = .env 또는 환경변수로 override
#   미설정 → 로컬 태그 사용
: "${DOCKERHUB_USER:=local}"
# dev-builder = Dockerfile 의 `builder` 스테이지(런타임 ENTRYPOINT 없음)
#   이 태그 문자열 = docker-compose.dev.yml 과 일치 필수
#   bringup = 그 override 를 병합해 바로 이 이미지들을 `up`
YOLO_IMAGE="docker.io/${DOCKERHUB_USER}/ros2-jazzy-yolo:dev-builder"

# 실제 사용 이미지 좌표 명시 출력(목적 = 조용한 기본값 폴백 방지 + 실행 기록(run-manifest) 추적)
printf 'INFO: build target — YOLO=%s\n' "${YOLO_IMAGE}"
if [[ "${DOCKERHUB_USER}" == "local" ]]; then
    printf 'INFO: DOCKERHUB_USER unset → using local dev tag (cannot publish, set coordinates via .env).\n'
fi

TOTAL=3
step() { printf '\n[%d/%d] %s\n' "$1" "${TOTAL}" "$2"; }

#######################################
# 이미지 레이어 히스토리의 자격증명(credential) 흔적 부재 확인(secret 위생)
#   이미지에 1회 구워지면 레지스트리 노출 = 비가역 → 필수 검사
# Arguments:
#   $1 - 검사할 도커 이미지 태그
# Outputs:
#   흔적 발견 시 stderr 로 실패 메시지
# Returns:
#   흔적 발견 시 1
#######################################
secret_scan() {
    local image="$1"
    # 변수 이름만으로 판단 불가(`openai` = pip 패키지 이름이기도 함)
    # 유출 판정 대상 = 값 대입 흔적(NAME=값) 또는 OpenAI 키 리터럴(sk-…) 만
    if docker history --no-trunc "${image}" \
        | grep -iE '(API_?KEY|TOKEN|SECRET|PASSWD|PASSWORD)[[:space:]]*=[[:space:]]*[^[:space:]]|sk-[A-Za-z0-9_-]{16,}'; then
        echo "  ✗ secret trace found — ${image}" >&2
        return 1
    fi
    echo "  ✓ no secret trace — ${image}"
}

#######################################
# 컨테이너 안 가벼운 import 확인(isolated import smoke) 실행
# builder 스테이지 = 런타임 ENTRYPOINT 없음
#   → python 실행 전에 여기서 ROS2 + 오버레이(overlay) 직접 source
#   준비 과정 = containers/entrypoint.sh + dev/bashrc 와 동일
# pip 패키지 위치 = /usr/local/lib/python3.X/dist-packages = system python 기본 sys.path → 경로 주입 불필요
# `bash -c 'SCRIPT' "$pyexpr"` = pyexpr 를 컨테이너 안 $0 에 바인딩 후 python3 -c "$0" 로 전달
#   목적 = 따옴표 중첩으로 깨지는 escaping 회피
# Arguments:
#   $1 - 실행할 도커 이미지 태그
#   $2 - python3 -c 로 넘길 파이썬 코드 문자열
#######################################
smoke() {
    local image="$1" pyexpr="$2"
    docker run --rm "${image}" bash -c '
        set +u
        source "/opt/ros/${ROS_DISTRO}/setup.bash"
        [ -f /ws/install/setup.bash ] && source /ws/install/setup.bash
        exec python3 -c "$0"
    ' "${pyexpr}"
}

# cobot2 소스 = 외부 관리(externalized)
#   소스 위치 = 레포 아님, ${DSR_WORKSPACE}/src/cobot2
# yolo Dockerfile = 빌드 컨텍스트(REPO_ROOT) 기준으로 cobot_ws/src/cobot2/yolo_container/... 를 COPY
#   → 검증된 소스를 빌드 컨텍스트 안으로 복사(/cobot_ws/src/ 경로 = gitignore 대상)
# 사용 소스 = setup-app 의 obtain_cobot2 가 확인한 그 소스(${DSR_WORKSPACE}/src/cobot2)
#   레포에 남은 오래된(stale) 부분 복사본 = 덮어씀
COBOT2_SRC="${DSR_WORKSPACE}/src/cobot2"
COBOT2_CTX="${REPO_ROOT}/cobot_ws/src/cobot2"
# yolo Dockerfile 이 COPY 하는 정확한 패키지 디렉토리 목록(빌드 컨텍스트 기준 경로)
#   확인 대상 = yolo_container 상위 폴더 아님, 이 말단(leaf) 경로들 직접
#   → 소스 부분 존재 시(예: od_msg 있음 + object_detection 없음) 여기서 즉시 크게 실패
#   미확인 시 = 수 분 걸리는 torch 레이어를 다 받은 뒤에야 BuildKit 이 알 수 없는 '<path>: not found' 로 폭발
#   이 목록 = yolo Dockerfile 의 COPY 줄과 항상 일치 필수
COBOT2_REQUIRED=(
    yolo_container/od_msg
    yolo_container/object_detection
)
missing=()
for rel in "${COBOT2_REQUIRED[@]}"; do
    [[ -d "${COBOT2_SRC}/${rel}" ]] || missing+=("${rel}")
done
if (( ${#missing[@]} )); then
    echo "build-all: cobot2 source incomplete at ${COBOT2_SRC} — missing: ${missing[*]}" >&2
    echo "           Place the full cobot2 source there (setup-app obtain_cobot2) before building." >&2
    exit 1
fi
printf 'INFO: staging cobot2 source %s → %s (build context)\n' "${COBOT2_SRC}" "${COBOT2_CTX}"
rm -rf "${COBOT2_CTX}"
mkdir -p "$(dirname "${COBOT2_CTX}")"
cp -aT "${COBOT2_SRC}" "${COBOT2_CTX}"   # -T: cobot2 그 자체로 복사(남아있는 cobot2/ 폴더 안으로 중첩되지 않게)
# 복사된 빌드 컨텍스트의 말단(leaf) 경로 실재 여부 확인
#   검출 대상 = 부분 복사 / 잘못된 DSR_WORKSPACE
#   검출 시점 = BuildKit 이 거부할 컨텍스트로 torch 다운로드를 낭비하기 전
for rel in "${COBOT2_REQUIRED[@]}"; do
    [[ -d "${COBOT2_CTX}/${rel}" ]] || { echo "build-all: staging incomplete — ${COBOT2_CTX}/${rel} absent after copy." >&2; exit 1; }
done

step 1 "build yolo-detection (torch cu${CUDA_VERSION//./} + ultralytics + numpy<2)"
docker build --pull \
    -f "${REPO_ROOT}/containers/yolo-detection/Dockerfile" \
    --target builder \
    --build-arg ROS_DISTRO="${ROS_DISTRO}" \
    --build-arg CUDA_VERSION="${CUDA_VERSION}" \
    -t "${YOLO_IMAGE}" \
    "${REPO_ROOT}"

step 2 "secret hygiene scan (docker history)"
secret_scan "${YOLO_IMAGE}"

step 3 "isolated import smoke — yolo (no GPU/model needed)"
smoke "${YOLO_IMAGE}" \
"import torch, torchvision, ultralytics, cv2, numpy
from od_msg.srv import SrvDepthPosition
import object_detection.yolo, object_detection.realsense, object_detection.detection
assert numpy.__version__.startswith('1.'), numpy.__version__
print('  yolo import OK — numpy', numpy.__version__)"

printf '\n✅ build gate PASS — yolo image built + secret hygiene + import smoke passed.\n'
printf '   GPU runtime / service round-trip / od_msg hash consistency are verified after host e2e (out of scope for this stage).\n'
