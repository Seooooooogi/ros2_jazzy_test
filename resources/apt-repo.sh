#!/usr/bin/env bash
# shellcheck shell=bash
# resources/apt-repo.sh — apt repo + keyring 등록 중앙화 (멱등).
# source 전용 라이브러리 — set -euo 를 여기 두지 않는다(호출 진입점이 셸 옵션을 소유).
#
# add_apt_repo: keyring dir 보장 → GPG 키(없을 때만, raw/dearmor) → chmod a+r →
#               apt source list 멱등 기록 → (기본) apt-get update.
# 키 파일명·signed-by 경로는 호출자가 vendor 형식 그대로 전달(임의 변환 금지 — repo 인증 깨짐).
# vendor 별 키 처리 차이(다운로더 플래그·dearmor write·list 비교)는 인자로 보존한다.
#
# Usage:
#   add_apt_repo \
#       --key-file PATH --key-url URL \
#       [--mode raw|dearmor] [--downloader curl|curl-sSf|wget] [--key-write tee|gpg-o] \
#       --list-file PATH \
#       { --list-line "deb ..." | --list-url URL --list-sed "s#..#..#g" } \
#       [--list-cmp grep|cat] [--no-update]
#
#   raw     = 키를 그대로 저장(armored .asc / 원본). 항상 `sudo curl -fsSL URL -o KEY`.
#   dearmor = `<downloader> URL | gpg --dearmor | sudo tee KEY`  (--key-write tee, 기본)
#             또는 `<downloader> URL | sudo gpg --dearmor -o KEY` (--key-write gpg-o)
#   list-cmp grep = 단일행 grep -qxF (기본) / cat = 다중행 전체 비교(upstream list+sed).

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
            *) echo "add_apt_repo: 알 수 없는 인자 '$1'" >&2; return 2;;
        esac
    done

    # 다운로더(→ stdout) 플래그 배열 — vendor 별 정확 보존.
    local -a dl
    case "${downloader}" in
        curl)     dl=(curl -fsSL);;
        curl-sSf) dl=(curl -sSf);;
        wget)     dl=(wget -qO-);;
        *) echo "add_apt_repo: 알 수 없는 downloader '${downloader}'" >&2; return 2;;
    esac

    # 1) keyring 디렉토리 + 키 (없을 때만 — idempotent).
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
            *) echo "add_apt_repo: 알 수 없는 mode '${mode}'" >&2; return 2;;
        esac
        sudo chmod a+r "${key_file}"
    fi

    # 2) apt source list — 동일 내용이면 재기록 안 함(중복/덮어쓰기 방지).
    local desired
    if [[ -n "${list_url}" ]]; then
        # upstream list 를 받아 signed-by 주입(sed). 다중행이라 cat 비교가 기본.
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

    # 3) apt 캐시 갱신 (호출자가 --no-update 면 생략 — repo-add 후 별도 update 가 따로 있을 때).
    if [[ "${do_update}" == "1" ]]; then
        sudo apt-get update
    fi
}
