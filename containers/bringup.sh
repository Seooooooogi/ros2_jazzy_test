#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# containers/bringup.sh · 통합 실행 스크립트
#   로봇 구동 + yolo 컨테이너 + host voice 노드 동시 기동 + 종료 시 확정 정리
#   사전 조건 = bash setup-app.sh 선행(워크스페이스 빌드 + yolo dev-builder 이미지)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# base + dev override 병합 = dev-builder 이미지(소스 live-mount + 컨테이너 안 colcon build)
COMPOSE_ARGS=(-f "${SCRIPT_DIR}/docker-compose.yml" -f "${SCRIPT_DIR}/docker-compose.dev.yml")

# config.sh = compose 파일의 값 치환(interpolate)용 env 공급
set -a
# shellcheck disable=SC1090,SC1091
source "${REPO_DIR}/resources/config.sh"
set +a

# OPENAI_API_KEY = 인스톨러 미취급, voice_processing 패키지의 resource/.env 담당

# ROS underlay + cobot2_ws 오버레이 source
set +u
# shellcheck disable=SC1090,SC1091
source "/opt/ros/${ROS_DISTRO}/setup.bash"
if [[ -f "${DSR_WORKSPACE}/install/setup.bash" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "${DSR_WORKSPACE}/install/setup.bash"
fi
set -u

# 정리 2회 실행 방지 플래그
_cleaned=0
# 애플리케이션 정리 = yolo 컨테이너 down + host voice 프로세스 kill
cleanup() {
    if [[ "${_cleaned}" -eq 1 ]]; then return 0; fi
    _cleaned=1
    echo "[bringup] stopping application containers (docker compose down)…"
    docker compose "${COMPOSE_ARGS[@]}" down --timeout 5 || true
    # `-- -PID` = 프로세스 그룹 전체에 신호 → 래퍼 + 노드 + 자손 동시 종료
    if [[ -n "${VOICE_PID:-}" ]] && kill -0 "${VOICE_PID}" 2>/dev/null; then
        echo "[bringup] stopping host voice node (pgid ${VOICE_PID})…"
        kill -TERM -- -"${VOICE_PID}" 2>/dev/null || true
        wait "${VOICE_PID}" 2>/dev/null || true
    fi
}
trap cleanup INT TERM EXIT

# 지정 서비스 컨테이너의 colcon build 완료까지 대기(빌드 실패 또는 타임아웃 → 1)
wait_build() {
    local svc="$1" deadline=$(( SECONDS + 600 )) logs
    echo "[bringup] waiting for ${svc} colcon build…"
    while (( SECONDS < deadline )); do
        # grep -q 아님, 명령 치환 사용(파이프 close 로 인한 오판 회피)
        logs="$(docker logs "${svc}" 2>&1)" || true
        # 빌드 종료 판정 = colcon 의 Summary 줄 + failed/aborted 표시 유무
        if grep -qE 'Summary: [0-9]+ package' <<<"${logs}"; then
            if grep -qE 'package(s)? (failed|aborted)' <<<"${logs}"; then
                echo "[bringup] ${svc} colcon build FAILED — see: docker logs ${svc}" >&2
                return 1
            fi
            echo "[bringup] ${svc} build ready."
            return 0
        fi
        sleep 3
    done
    echo "[bringup] timeout: ${svc} build unfinished — see: docker logs ${svc}" >&2
    return 1
}

echo "[bringup] starting application containers (docker compose up -d)…"
# 선행 초기화 = 깨끗한 상태 확보
docker compose "${COMPOSE_ARGS[@]}" down --timeout 5 || true
docker compose "${COMPOSE_ARGS[@]}" up -d

wait_build yolo-detection

echo "[bringup] launching yolo node inside the dev container…"
# docker exec = 비대화 모드 → dev bashrc 직접 source
# img_node: 접두사 = ImgNode 에만 네임스페이스 remap 적용
docker exec -d yolo-detection bash -c 'source /root/.bashrc; exec ros2 run object_detection object_detection --ros-args -r img_node:__ns:=/camera'

# host voice 노드 = 컨테이너 아님, host 직접 실행(마이크 하드웨어 종속)
# set -m(job control) → 이 백그라운드 잡이 프로세스 그룹 리더 → cleanup 이 그룹째 종료
echo "[bringup] launching host voice node (ros2 run voice_processing get_keyword)…"
set -m
ros2 run voice_processing get_keyword &
VOICE_PID=$!
set +m

# 기동 확인 = 래퍼 생존 여부
sleep 5
if ! kill -0 "${VOICE_PID}" 2>/dev/null; then
    echo "[bringup] host voice node died on startup — 위 출력에서 원인 확인" >&2
    echo "          (모델/의존성 점검: bash resources/app-install.sh voice)" >&2
    exit 1
fi
echo "[bringup] host voice node up (pgid ${VOICE_PID})"

echo "[bringup] launching robot driver + gripper + camera — Ctrl+C tears everything down."
# camera 기본값 반전 = 사용자 미지정 시에만 camera:=true 부착
LAUNCH_ARGS=("$@")
camera_set=0
for arg in "$@"; do
    [[ "${arg}" == camera:=* ]] && camera_set=1
done
if [[ "${camera_set}" -eq 0 ]]; then
    LAUNCH_ARGS+=(camera:=true)
fi
ros2 launch m0609_rg2_bringup bringup.launch.py "${LAUNCH_ARGS[@]}"
