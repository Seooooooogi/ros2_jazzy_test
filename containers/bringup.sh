#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# containers/bringup.sh — 로봇 구동과 yolo/voice 컨테이너를 함께 띄우고, 종료 시 컨테이너를 확실히 정리하는 통합 실행 스크립트.
#
# 로봇 드라이버 + 카메라(cobot2_bringup launch) 실행 + yolo/voice 컨테이너 생명주기(docker
# compose up -d)도 이 스크립트가 직접 관리. shell trap 설정 → Ctrl+C 시 컨테이너
# 확실히 정리.
#
# 왜 launch 가 아니라 별도 wrapper 스크립트인가: ROS2 launch 의 OnShutdown 핸들러 = 종료 도중 새 프로세스
# 시작 불가. → 거기에 `docker compose down` 등록해도 Ctrl+C 때 미실행 → 컨테이너 안 꺼지고
# Up 상태로 잔존(leak). 대신 이 shell 이 compose 직접 소유 + `trap … INT TERM EXIT` 설정 → launch 가
# 어떻게 끝나든 정리 보장(재현 실험으로 확인). 이제 launch 자체는 컨테이너 미관여(컨테이너 없이
# 로봇/카메라만 띄우려면 launch 직접 실행).
#
# 사전 조건: 먼저 `bash setup-app.sh` 실행(cobot2_bringup + 오버레이 빌드, dev-builder 이미지 빌드).
# launch 인자 = 그대로 전달:
#   bash containers/bringup.sh                       # 가상(emulator) + 카메라 + 컨테이너
#   bash containers/bringup.sh mode:=real            # 실제 로봇
#   bash containers/bringup.sh mode:=virtual camera:=false
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# base + dev override 합치면 dev-builder 이미지(소스 live-mount + 컨테이너 안에서 colcon build).
# up 과 down 은 반드시 같은 -f 조합 필요 → trap 과 up 호출이 함께 재사용하도록 하나의 배열로 묶음.
COMPOSE_ARGS=(-f "${SCRIPT_DIR}/docker-compose.yml" -f "${SCRIPT_DIR}/docker-compose.dev.yml")

# config.sh = compose 파일이 값 치환(interpolate)에 쓰는 env(CYCLONEDDS_XML / ROS_DOMAIN_ID / RMW /
# DOCKERHUB_USER / *_TAG) + voice 서비스가 읽는 ../.env 를 채움. 한 번만 source → trap 의 down 도 그대로 재사용.
set -a
# shellcheck disable=SC1090,SC1091
source "${REPO_DIR}/resources/config.sh"
set +a

# ROS underlay + cobot_ws 오버레이 source 해야 `ros2 launch cobot2_bringup` 인식.
# set +u: ROS 의 setup.bash 는 `set -u` 상태에서 정의 안 된(unbound) 변수를 참조하기 때문.
set +u
# shellcheck disable=SC1090,SC1091
source "/opt/ros/${ROS_DISTRO}/setup.bash"
if [[ -f "${DSR_WORKSPACE}/install/setup.bash" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "${DSR_WORKSPACE}/install/setup.bash"
fi
set -u

# 이 컨테이너들 = 이 shell 소유 → 어떤 식으로 끝나든(Ctrl+C / 에러 / 정상 종료) 정리 필요.
# INT/TERM trap 과 EXIT trap 둘 다 걸려 있어 정리가 두 번 실행될 수 있음 → _cleaned 로 한 번만 돌게 차단.
_cleaned=0
#######################################
# 애플리케이션 컨테이너 정리(docker compose down). 종료 방식(Ctrl+C / 에러 / 정상)과 무관하게 호출.
# Globals:
#   _cleaned (읽고 씀), COMPOSE_ARGS (읽음)
# Outputs:
#   stdout 에 정리 시작 안내 1줄.
#######################################
cleanup() {
    if [[ "${_cleaned}" -eq 1 ]]; then return 0; fi
    _cleaned=1
    echo "[bringup] stopping application containers (docker compose down)…"
    docker compose "${COMPOSE_ARGS[@]}" down --timeout 5 || true
}
trap cleanup INT TERM EXIT

#######################################
# 지정한 서비스 컨테이너의 colcon build 끝날 때까지 대기.
# dev 명령(docker-compose.dev.yml) = `… ; colcon build ; sleep infinity` 형태 → 노드 자동 실행 안 됨.
# 그 명령에 set -e 없어 빌드 실패해도 컨테이너는 Up 으로 잔존. 그래서 컨테이너 상태가 아니라 이번
# 실행의 colcon 완료 로그 기준으로 판단. 파일/실행파일 존재 여부로 판단하면 경합(race) 발생:
# named volume 이 이미지에 미리 구워진 /ws/install 을 먼저 채우는데, 명령이 그걸 지우고 다시 빌드하기 때문.
# 로그는 컨테이너 실행마다 새로 쌓이므로 그런 경합 없음.
# Arguments:
#   $1 - 대기할 서비스(=컨테이너) 이름
# Outputs:
#   stdout 에 진행 상황, 실패/타임아웃 시 stderr 에 안내.
# Returns:
#   빌드 성공 0, 빌드 실패 또는 타임아웃 1.
#######################################
wait_build() {
    local svc="$1" deadline=$(( SECONDS + 600 )) logs
    echo "[bringup] waiting for ${svc} colcon build…"
    while (( SECONDS < deadline )); do
        # `docker logs | grep -q` 대신 명령 치환(command substitution)을 쓰는 이유: grep -q 는 첫 매치에서
        # 파이프를 닫아 docker logs 에 SIGPIPE 를 보냄 → pipefail 에서는 파이프라인이 그 실패를 보고 →
        # 실제로 매치됐는데도 if 가 거짓이 됨. 치환은 로그 전체를 먼저 읽으므로 끊길 파이프 없음.
        logs="$(docker logs "${svc}" 2>&1)" || true
        # colcon 은 빌드를 마치면 `Summary: N package[s] finished` 줄을 찍음 — N=1 이면 package(단수)라
        # (voice_container 는 패키지가 정확히 1개), 단·복수 상관없이 매칭. 빌드 실패해도 Summary 줄은
        # 찍힘("Summary: 0 packages finished") + "M package[s] failed/aborted" 가 같이 나옴. 그래서 Summary 가
        # 뜨면, failed/aborted 표시가 하나라도 있으면 빌드 실패로 판정. ("had stderr output" 은 경고이지 실패 아님.)
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
# 먼저 깨끗한 상태로 초기화: 이전 실행의 컨테이너가 Up 인 채 잔존 가능(SIGKILL / 호스트 크래시로
# trap 이 안 돌았던 경우). container_name 이 고정이라 그냥 `up -d` 하면 그 컨테이너 재사용 → 아래
# `docker exec -d` 가 옛 노드 위에 `ros2 run` 을 하나 더 적재(서비스 서버 중복). 그래서 먼저 `down` →
# `up` 이 항상 노드 1개짜리 컨테이너를 새로 생성. (build/install named volume 은 유지되지만 dev 명령이 어차피 지우고 다시 빌드.)
docker compose "${COMPOSE_ARGS[@]}" down --timeout 5 || true
docker compose "${COMPOSE_ARGS[@]}" up -d

wait_build yolo-detection
wait_build voice-processing

echo "[bringup] launching yolo/voice nodes inside the dev containers…"
# docker exec = 비대화(non-interactive) 모드 → ~/.bashrc 자동 source 안 함. 그래서 dev bashrc 를
# 직접 source(dev override 가 /root/.bashrc 로 mount). ROS + 오버레이 + venv PYTHONPATH 가 잡혀,
# 대화형 exec 이 받는 것과 같은 환경.
docker exec -d yolo-detection  bash -c 'source /root/.bashrc; exec ros2 run object_detection object_detection'
docker exec -d voice-processing bash -c 'source /root/.bashrc; exec ros2 run voice_processing get_keyword'

echo "[bringup] launching robot driver + camera — Ctrl+C tears everything down."
ros2 launch cobot2_bringup bringup_all.launch.py "$@"
