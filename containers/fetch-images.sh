#!/usr/bin/env bash
# Phase 4 application 이미지 확보 — 빌드 대신 공개 구글 드라이브에서 tar 를 받아 docker load.
#
# 클린설치(install.sh step14)의 기본 경로다. 이미지를 직접 빌드/검증(이미지 제작 머신)하려면
# containers/build-all.sh 를 쓴다. 본 스크립트는 그 산출물(docker save tar)을 받아 재현만 한다.
#
# 동작:
#   1) 대상 이미지가 이미 로컬에 있으면 skip (멱등 — 재실행/재개 안전).
#   2) 공개 드라이브 file ID 로 tar 다운로드 (대용량 virus-scan confirm 토큰 처리).
#   3) SHA256 검증 (config 에 핀된 값과 대조) — 손상/위변조 차단.
#   4) gz/zip 이면 해제한 뒤 docker load.
#
# file ID / SHA256 은 config.sh 에 핀한다(공개 링크 ID 는 secret 아님). 업로드 후 ID 를 채운다.
# 사용: bash containers/fetch-images.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=resources/config.sh
source "${REPO_ROOT}/resources/config.sh"

# 다운로드 작업 디렉토리(머신 종속 산출물 — 레포 추적 안 함).
WORKDIR="${IMAGE_FETCH_DIR:-${STATE_DIR}/images}"
mkdir -p "${WORKDIR}"

# 이미지 정의: "로컬태그|드라이브ID|sha256|파일명". build-all.sh 의 이미지 좌표와 동일 기본값.
IMAGES=(
    "docker.io/${DOCKERHUB_USER:-local}/ros2-jazzy-yolo:${YOLO_TAG:-dev}|${YOLO_IMAGE_GDRIVE_ID:-}|${YOLO_IMAGE_SHA256:-}|ros2-jazzy-yolo-dev.tar"
    "docker.io/${DOCKERHUB_USER:-local}/ros2-jazzy-voice:${VOICE_TAG:-dev}|${VOICE_IMAGE_GDRIVE_ID:-}|${VOICE_IMAGE_SHA256:-}|ros2-jazzy-voice-dev.tar"
)
TOTAL="${#IMAGES[@]}"

# 공개 구글 드라이브 대용량 파일 다운로드. >100MB 는 1차 요청에 virus-scan confirm form(HTML)을
# 돌려주므로 confirm/uuid 토큰을 뽑아 2차 요청해야 실제 바이너리를 받는다. 작은 파일은 1차가 곧 파일.
gdrive_download() {
    local id="$1" out="$2"
    local base="https://drive.usercontent.google.com/download"
    local cookie; cookie="$(mktemp)"
    local html; html="$(curl -sL -c "${cookie}" "${base}?id=${id}&export=download")"
    if printf '%s' "${html}" | grep -q 'name="confirm"'; then
        local confirm uuid
        confirm="$(printf '%s' "${html}" | grep -o 'name="confirm" value="[^"]*"' | sed -E 's/.*value="([^"]*)".*/\1/')"
        uuid="$(printf '%s' "${html}" | grep -o 'name="uuid" value="[^"]*"' | sed -E 's/.*value="([^"]*)".*/\1/')"
        curl -fL -# --retry 3 --retry-delay 5 -c "${cookie}" -o "${out}" \
            "${base}?id=${id}&export=download&confirm=${confirm}&uuid=${uuid}"
    else
        curl -fL -# --retry 3 --retry-delay 5 -c "${cookie}" -o "${out}" \
            "${base}?id=${id}&export=download"
    fi
    rm -f "${cookie}"
}

n=0
for entry in "${IMAGES[@]}"; do
    n=$((n + 1))
    IFS='|' read -r tag id sha fname <<< "${entry}"
    printf '\n[%d/%d] %s\n' "${n}" "${TOTAL}" "${tag}"

    if docker image inspect "${tag}" >/dev/null 2>&1; then
        echo "  ✓ 이미 로컬에 존재 — skip"
        continue
    fi
    if [[ -z "${id}" ]]; then
        echo "  ✗ 드라이브 file ID 미설정 (config.sh 의 *_IMAGE_GDRIVE_ID)." >&2
        echo "    업로드 후 ID 를 채우거나, 직접 빌드는 containers/build-all.sh 를 실행하세요." >&2
        exit 1
    fi

    tarpath="${WORKDIR}/${fname}"
    echo "  · 다운로드 → ${tarpath}"
    gdrive_download "${id}" "${tarpath}"

    if [[ -n "${sha}" ]]; then
        echo "  · SHA256 검증"
        echo "${sha}  ${tarpath}" | sha256sum -c - \
            || { echo "  ✗ 체크섬 불일치 — 손상/위변조 의심, 중단" >&2; exit 1; }
    else
        echo "  ! SHA256 미설정 — 무결성 검증 생략(config 에 핀 권장)" >&2
    fi

    # 압축 해제 분기. docker load 가 gzip 은 자동 인식하나, 명시 해제로 gz/zip 모두 일반화.
    case "${tarpath}" in
        *.gz)  echo "  · gunzip"; gunzip -f "${tarpath}"; tarpath="${tarpath%.gz}";;
        *.zip) echo "  · unzip";  unzip -o "${tarpath}" -d "${WORKDIR}"; tarpath="${WORKDIR}/$(basename "${tarpath}" .zip).tar";;
    esac

    echo "  · docker load"
    docker load -i "${tarpath}"
    rm -f "${tarpath}"          # load 후 tar 불필요 — 디스크 회수(이미지 존재로 재실행 skip)
    echo "  ✓ load 완료"
done

echo
echo "✅ 이미지 확보 완료 — ${TOTAL} 개. (직접 빌드/검증은 containers/build-all.sh)"
