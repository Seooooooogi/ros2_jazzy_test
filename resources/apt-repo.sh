#!/usr/bin/env bash
# =============================================================
#  Cobot2 Jazzy Installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck shell=bash
# resources/apt-repo.sh — apt repo 와 키링(apt 서명 키) 등록을 한곳에서 처리(멱등).
# source 전용 라이브러리 — set -euo 를 여기 두지 않는다(호출 진입점이 셸 옵션을 소유).
#
# add_apt_repo: 키링 디렉터리 확보 → GPG 키 준비(없을 때만, raw/dearmor 방식) → chmod a+r →
#               apt source list 를 멱등하게(같은 명령을 여러 번 실행해도 결과가 같게) 기록 → (기본값) apt-get update.
# 호출자 = 키 파일명 / signed-by 경로를 vendor 가 쓰는 형식 그대로 전달(임의 변경 금지 — 변경 시 repo 서명 검증 깨짐).
# vendor 마다 다른 키 처리 방식(다운로더 플래그, dearmor 기록, list 비교) = 인자로 받아 그대로 유지.
#
# 사용법:
#   add_apt_repo \
#       --key-file PATH --key-url URL \
#       [--mode raw|dearmor] [--downloader curl|curl-sSf|wget] [--key-write tee|gpg-o] \
#       --list-file PATH \
#       { --list-line "deb ..." | --list-url URL --list-sed "s#..#..#g" } \
#       [--list-cmp grep|cat] [--no-update]
#
#   raw     = 키를 받은 그대로 저장(armored .asc / 원본). 항상 `sudo curl -fsSL URL -o KEY`.
#   dearmor = 바이너리 GPG 키로 변환해 저장. `<downloader> URL | gpg --dearmor | sudo tee KEY`  (--key-write tee, 기본값)
#             또는 `<downloader> URL | sudo gpg --dearmor -o KEY` (--key-write gpg-o)
#   list-cmp grep = 한 줄만 grep -qxF 로 비교(기본값) / cat = 여러 줄 전체 비교(upstream list+sed).

add_apt_repo() {
    local key_file="" key_url="" mode="raw" downloader="curl" key_write="tee"
    local list_file="" list_line="" list_url="" list_sed="" list_cmp="grep" do_update=1
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key-file)   key_file="$2";   shift 2;;
            --key-url)    key_url="$2";    shift 2;;
            --mode)       mode="$2";       shift 2;;
            --downloader) downloader="$2"; shift 2;;
            --key-write)  key_write="$2";  shift 2;;
            --list-file)  list_file="$2";  shift 2;;
            --list-line)  list_line="$2";  shift 2;;
            --list-url)   list_url="$2";   shift 2;;
            --list-sed)   list_sed="$2";   shift 2;;
            --list-cmp)   list_cmp="$2";   shift 2;;
            --no-update)  do_update=0;     shift;;
            *) echo "add_apt_repo: unknown argument '$1'" >&2; return 2;;
        esac
    done

    # 다운로더 플래그 배열(키를 stdout 으로 내보냄). vendor 마다 달라서 그대로 보존.
    local -a dl
    case "${downloader}" in
        curl)     dl=(curl -fsSL);;
        curl-sSf) dl=(curl -sSf);;
        wget)     dl=(wget -qO-);;
        *) echo "add_apt_repo: unknown downloader '${downloader}'" >&2; return 2;;
    esac

    # 1) 키링 디렉터리 + 키(없을 때만 생성 — 멱등).
    sudo install -m 0755 -d "$(dirname "${key_file}")"
    if [[ ! -f "${key_file}" ]]; then
        case "${mode}" in
            raw)
                sudo curl -fsSL "${key_url}" -o "${key_file}"
                ;;
            dearmor)
                if [[ "${key_write}" == "gpg-o" ]]; then
                    "${dl[@]}" "${key_url}" | sudo gpg --dearmor -o "${key_file}"
                else
                    "${dl[@]}" "${key_url}" | gpg --dearmor | sudo tee "${key_file}" >/dev/null
                fi
                ;;
            *) echo "add_apt_repo: unknown mode '${mode}'" >&2; return 2;;
        esac
        sudo chmod a+r "${key_file}"
    fi

    # 2) apt source list — 내용 같으면 재기록 안 함(중복 추가·덮어쓰기 방지).
    local desired
    if [[ -n "${list_url}" ]]; then
        # upstream 의 list 를 받아 signed-by 경로를 sed 로 삽입. 여러 줄이라 cat 비교가 기본값.
        desired="$("${dl[@]}" "${list_url}" | sed "${list_sed}")"
    else
        desired="${list_line}"
    fi
    local need_write=1
    if [[ -f "${list_file}" ]]; then
        if [[ "${list_cmp}" == "cat" ]]; then
            [[ "$(cat "${list_file}")" == "${desired}" ]] && need_write=0
        else
            grep -qxF "${desired}" "${list_file}" && need_write=0
        fi
    fi
    if [[ "${need_write}" == "1" ]]; then
        echo "${desired}" | sudo tee "${list_file}" >/dev/null
    fi

    # 3) apt 캐시 갱신(호출자가 --no-update 를 주면 건너뜀 — repo 추가 뒤에 별도 update 가 이어질 때).
    if [[ "${do_update}" == "1" ]]; then
        sudo apt-get update
    fi
}
