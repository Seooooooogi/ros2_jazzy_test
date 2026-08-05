#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# containers/bringup.sh · 통합 실행 스크립트
#   로봇 구동 + yolo 컨테이너 + host voice 노드 동시 기동 + 종료 시 확정 정리
#
# 이 스크립트가 직접 관리하는 것
#   로봇 드라이버 + 그리퍼 + 카메라(m0609_rg2_bringup launch)
#   yolo 컨테이너 생명주기(docker compose up -d)
#   host voice 노드(ros2 run voice_processing get_keyword)
#     컨테이너 아님 = 마이크 하드웨어 종속 → host 실행
#   shell trap 설정 → Ctrl+C 시 컨테이너 down + host voice 프로세스 kill
#
# launch 아닌 별도 wrapper 스크립트인 이유
#   ROS2 launch 의 OnShutdown 핸들러 = 종료 도중 새 프로세스 시작 불가
#   → `docker compose down` 을 등록해도 Ctrl+C 때 미실행
#   → 컨테이너 미종료 + Up 상태 잔존(leak)
#   대안 = 이 shell 이 compose + voice 프로세스를 직접 소유 + `trap … INT TERM EXIT` 설정
#   → launch 종료 방식과 무관하게 정리 보장(재현 실험으로 확인)
#   launch 자체 = 미관여(컨테이너/voice 없이 로봇/카메라만 기동하려면 launch 직접 실행)
#
# 사전 조건: `bash setup-app.sh` 선행
#   m0609_rg2_bringup + 오버레이 빌드 / host voice Python 설치 / yolo dev-builder 이미지 빌드
# launch 인자(mode / host / port / camera / rviz / rt_host) = 그대로 전달:
#   bash containers/bringup.sh                       # 가상(emulator) + 카메라 + yolo 컨테이너 + host voice
#   bash containers/bringup.sh mode:=real            # 실제 로봇
#   bash containers/bringup.sh camera:=false          # 카메라 없이 (yolo = 대기 상태)
#                                                     # mode 무관하게 유효, real 에서도 off
# camera 미지정 → 이 스크립트가 camera:=true 부착
#   yolo 파이프라인 = 카메라 토픽 의존
#   → launch 기본값(false, standalone 개발용)을 여기서 반전
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# base + dev override 병합 = dev-builder 이미지(소스 live-mount + 컨테이너 안 colcon build)
# up / down = 같은 -f 조합 필수 → trap 과 up 이 공유하는 단일 배열로 묶음
COMPOSE_ARGS=(-f "${SCRIPT_DIR}/docker-compose.yml" -f "${SCRIPT_DIR}/docker-compose.dev.yml")

# config.sh = compose 파일의 값 치환(interpolate)용 env 공급
#   대상 = CYCLONEDDS_XML / ROS_DOMAIN_ID / RMW / DOCKERHUB_USER / *_TAG
#   source 1회 → trap 의 down 도 그대로 재사용
set -a
# shellcheck disable=SC1090,SC1091
source "${REPO_DIR}/resources/config.sh"
set +a

# OPENAI_API_KEY = 인스톨러 미취급
#   voice_processing 노드 = 자기 패키지 resource/.env(colcon 빌드 내장)를 load_dotenv 로 직접 독해
#   → bringup 의 env 주입 불필요

# ROS underlay + cobot2_ws 오버레이 source 필요 → `ros2 launch m0609_rg2_bringup` 인식
#   패키지 링크 = setup-app.sh 의 obtain_m0609 가 이 워크스페이스 src 에 생성
# set +u 이유: ROS 의 setup.bash = `set -u` 상태에서 미정의(unbound) 변수 참조
set +u
# shellcheck disable=SC1090,SC1091
source "/opt/ros/${ROS_DISTRO}/setup.bash"
if [[ -f "${DSR_WORKSPACE}/install/setup.bash" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "${DSR_WORKSPACE}/install/setup.bash"
fi
set -u

# 이 컨테이너들 = 이 shell 소유 → 종료 방식(Ctrl+C / 에러 / 정상) 무관하게 정리 필요
# INT/TERM trap + EXIT trap 동시 등록 → 정리 2회 실행 가능 → _cleaned 로 1회만 통과
_cleaned=0
#######################################
# 애플리케이션 정리 = yolo 컨테이너 down + host voice 프로세스 kill
# 호출 조건 = 종료 방식(Ctrl+C / 에러 / 정상) 무관
# Globals:
#   _cleaned (읽고 씀), COMPOSE_ARGS (읽음)
#   VOICE_PID (읽음. trap 정의 시점엔 미정의 가능)
# Outputs:
#   stdout 에 정리 안내
#######################################
cleanup() {
    if [[ "${_cleaned}" -eq 1 ]]; then return 0; fi
    _cleaned=1
    echo "[bringup] stopping application containers (docker compose down)…"
    docker compose "${COMPOSE_ARGS[@]}" down --timeout 5 || true
    # host voice 노드 = 이 shell 이 백그라운드로 소유(VOICE_PID 평가 시점 = trap 발동 시 → 정의 전 발동돼도 안전)
    # `-- -PID` = 프로세스 그룹 전체에 신호
    #   기동부의 `set -m` → PGID == VOICE_PID
    #   → `ros2 run` 래퍼 + 그 자식인 실제 노드 + 노드가 띄운 자손까지 동시 종료
    #   래퍼만 kill → 노드가 마이크를 점유한 채 orphan 잔존 → 다음 실행과 충돌
    if [[ -n "${VOICE_PID:-}" ]] && kill -0 "${VOICE_PID}" 2>/dev/null; then
        echo "[bringup] stopping host voice node (pgid ${VOICE_PID})…"
        kill -TERM -- -"${VOICE_PID}" 2>/dev/null || true
        wait "${VOICE_PID}" 2>/dev/null || true
    fi
}
trap cleanup INT TERM EXIT

#######################################
# 지정 서비스 컨테이너의 colcon build 완료까지 대기
# dev 명령(docker-compose.dev.yml) = `… ; colcon build ; sleep infinity` 형태 → 노드 자동 실행 없음
#   그 명령에 set -e 없음 → 빌드 실패해도 컨테이너는 Up 으로 잔존
#   → 판단 기준 = 컨테이너 상태 아님, 이번 실행의 colcon 완료 로그
# 파일/실행파일 존재 여부로 판단 시 경합(race) 발생
#   named volume = 이미지에 미리 구워진 /ws/install 을 먼저 채움
#   명령 = 그것을 삭제하고 재빌드
# 로그 = 컨테이너 실행마다 새로 축적 → 그런 경합 없음
# Arguments:
#   $1 - 대기할 서비스(=컨테이너) 이름
# Outputs:
#   stdout 에 진행 상황, 실패/타임아웃 시 stderr 에 안내
# Returns:
#   빌드 성공 0 / 빌드 실패 또는 타임아웃 1
#######################################
wait_build() {
    local svc="$1" deadline=$(( SECONDS + 600 )) logs
    echo "[bringup] waiting for ${svc} colcon build…"
    while (( SECONDS < deadline )); do
        # `docker logs | grep -q` 아님, 명령 치환(command substitution) 사용
        #   grep -q = 첫 매치에서 파이프 close → docker logs 에 SIGPIPE
        #   → pipefail 에서 파이프라인이 그 실패를 보고 → 실제 매치인데도 if 가 거짓
        #   치환 = 로그 전체를 먼저 독해 → 끊길 파이프 없음
        logs="$(docker logs "${svc}" 2>&1)" || true
        # colcon = 빌드 종료 시 `Summary: N package[s] finished` 줄 출력
        #   N=1 → package(단수) / N>1 → packages(복수) → 단·복수 무관 매칭
        # 빌드 실패 시에도 Summary 줄 출력("Summary: 0 packages finished")
        #   + "M package[s] failed/aborted" 동반
        # → Summary 등장 시 failed/aborted 표시가 하나라도 있으면 빌드 실패 판정("had stderr output" = 경고, 실패 아님)
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
#   이전 실행 컨테이너가 Up 으로 잔존 가능(SIGKILL / 호스트 크래시로 trap 미실행)
#   container_name 고정 → 그대로 `up -d` 시 그 컨테이너 재사용
#   → 아래 `docker exec -d` 가 옛 노드 위에 `ros2 run` 을 추가 적재(서비스 서버 중복)
#   → 선 `down` 후 `up` = 항상 노드 1개짜리 컨테이너 신규 생성
#   build/install named volume = 유지되나 dev 명령이 어차피 삭제 후 재빌드
docker compose "${COMPOSE_ARGS[@]}" down --timeout 5 || true
docker compose "${COMPOSE_ARGS[@]}" up -d

wait_build yolo-detection

echo "[bringup] launching yolo node inside the dev container…"
# docker exec = 비대화(non-interactive) 모드 → ~/.bashrc 자동 source 없음
#   → dev bashrc 직접 source(dev override 가 /root/.bashrc 로 mount)
#   → ROS + 오버레이 확보 = 대화형 exec 과 동일 환경
# ImgNode = 카메라 토픽만 구독 → 노드 스코프 네임스페이스 remap 한 줄로 부착
# 'img_node:' 접두사 필수
#   프로세스 전역 __ns = 같은 프로세스의 object_detection_node 까지 이동
#   → robot_control 이 호출하는 /get_3d_position 경로 단절
docker exec -d yolo-detection bash -c 'source /root/.bashrc; exec ros2 run object_detection object_detection --ros-args -r img_node:__ns:=/camera'

# host voice 노드 = 컨테이너 아님
#   ROS underlay + cobot2_ws 오버레이 = 위에서 이미 source
#   get_keyword console_script shebang = system python
#     → app-install.sh voice 가 host 에 설치한 langchain/openwakeword 참조
#   기동 = 백그라운드 + PID 를 trap(cleanup)이 회수
#   마이크 = 데스크톱 PipeWire 기본(VOICE_MIC_DEVICE 로 override)
#
# `set -m`(job control) 채택 이유
#   `ros2 run` = 노드를 exec 하지 않고 자식 프로세스로 기동
#   ros2run/api/__init__.py = subprocess.Popen → $! = 래퍼 PID 일 뿐
#   → 래퍼 SIGTERM = 래퍼만 종료(핸들러 없음) + 노드는 마이크를 쥔 채 생존
#   job control on → 이 백그라운드 잡이 자기 프로세스 그룹의 리더(PGID == $!)
#   → cleanup 이 그룹 전체에 신호 → 노드 + 자손까지 동시 종료
# 대가 = 노드가 스크립트의 포그라운드 그룹 이탈 → 터미널 Ctrl+C 가 노드에 직접 전달 안 됨
#   → cleanup 의 그룹 kill = 유일한 종료 경로
#   두 변경 = 반드시 함께 유지
echo "[bringup] launching host voice node (ros2 run voice_processing get_keyword)…"
set -m
ros2 run voice_processing get_keyword &
VOICE_PID=$!
set +m

# 기동 확인
#   yolo = colcon 완료 로그로 pass/fail 판정
#   voice = fire-and-forget → import 실패·모델 누락·마이크 점유 사고가 조용히 은폐
#   실패 시 노드 = 수 초 내 사망
#   래퍼(`ros2 run`) = 자식 노드 종료 시 동반 종료 → 래퍼 생존 확인만으로 충분
#   여기서 exit → EXIT trap 의 cleanup 이 yolo 컨테이너까지 종료
sleep 5
if ! kill -0 "${VOICE_PID}" 2>/dev/null; then
    echo "[bringup] host voice node died on startup — 위 출력에서 원인 확인" >&2
    echo "          (모델/의존성 점검: bash resources/app-install.sh voice)" >&2
    exit 1
fi
echo "[bringup] host voice node up (pgid ${VOICE_PID})"

echo "[bringup] launching robot driver + gripper + camera — Ctrl+C tears everything down."
# camera 기본값 반전
#   m0609_rg2_bringup launch 의 camera 기본 = false (이유: standalone 개발 시 USB 카메라 미점유)
#   이 스크립트 = yolo 컨테이너 동반 기동 + 그 노드는 /camera/* 토픽 부재 시 조용히 대기만
#   → 사용자가 camera 미명시인 경우에만 camera:=true 부착
#   launch 의 중복 인자 우선순위에 의존하지 않고 직접 검사
#   사용자가 camera:=false 명시 → mode 무관하게 그대로 존중
LAUNCH_ARGS=("$@")
camera_set=0
for arg in "$@"; do
    [[ "${arg}" == camera:=* ]] && camera_set=1
done
if [[ "${camera_set}" -eq 0 ]]; then
    LAUNCH_ARGS+=(camera:=true)
fi
ros2 launch m0609_rg2_bringup bringup.launch.py "${LAUNCH_ARGS[@]}"
