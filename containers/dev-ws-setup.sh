#!/usr/bin/env bash
# dev 워크스페이스 생성 — 레포 cobot2_ws 의 컨테이너 패키지를 host 의 ~/yolo_ws·~/voice_ws 로 복사.
# docker-compose.dev.yml 이 이 경로(${WS}/src)를 컨테이너 /ws/src 에 bind-mount → 코드 수정 즉시 반영.
#
# 별도 워크스페이스라 거기서 자유롭게 편집·디버깅하고, 레포 공유는 수동으로 되돌려 커밋한다.
# (symlink 은 docker bind-mount 안에서 host 경로를 가리켜 컨테이너에서 깨지므로 복사 채택.)
#
# 멱등: 이미 있는 패키지 디렉토리는 건너뛴다(편집본 보호). --force 로 덮어쓰기.
# 사용: bash containers/dev-ws-setup.sh [--force]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=resources/config.sh
source "${REPO_ROOT}/resources/config.sh"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

SRC="${REPO_ROOT}/cobot2_ws"

# "대상WS|패키지...". yolo 는 object_detection 이 od_msg.srv 를 import 하므로 함께 복사.
ENTRIES=(
    "${YOLO_WS}|od_msg object_detection"
    "${VOICE_WS}|voice_processing"
)
TOTAL="${#ENTRIES[@]}"

n=0
for entry in "${ENTRIES[@]}"; do
    n=$((n + 1))
    IFS='|' read -r ws pkglist <<< "${entry}"
    read -ra pkgs <<< "${pkglist}"
    printf '[%d/%d] %s\n' "${n}" "${TOTAL}" "${ws}"
    mkdir -p "${ws}/src"
    for pkg in "${pkgs[@]}"; do
        dest="${ws}/src/${pkg}"
        if [[ -e "${dest}" && "${FORCE}" -ne 1 ]]; then
            echo "  · ${pkg}: 이미 존재 — skip (--force 로 덮어쓰기)"
            continue
        fi
        rm -rf "${dest}"
        cp -r "${SRC}/${pkg}" "${dest}"
        echo "  ✓ ${pkg} 복사"
    done
done

echo
echo "✅ dev 워크스페이스 준비 완료."
echo "  빌드: docker compose -f ${REPO_ROOT}/containers/docker-compose.yml -f ${REPO_ROOT}/containers/docker-compose.dev.yml build"
echo "  기동: docker compose -f ${REPO_ROOT}/containers/docker-compose.yml -f ${REPO_ROOT}/containers/docker-compose.dev.yml up -d yolo-detection"
echo "  진입: docker exec -it yolo-detection bash   # 안에서 colcon build --symlink-install && ros2 run object_detection object_detection"
