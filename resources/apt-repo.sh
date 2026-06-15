#!/usr/bin/env bash
# =============================================================
#  ros2_jazzy_test — ROS2 Jazzy workstation installer
#  Copyright (c) 2026 ROKEY bootcamp. All rights reserved.
# =============================================================
#
# shellcheck shell=bash
# resources/apt-repo.sh — centralized apt repo + keyring registration (idempotent).
# Source-only library — no `set -euo` here (the calling entry point owns shell options).
#
# add_apt_repo: ensure keyring dir → GPG key (only if absent, raw/dearmor) → chmod a+r →
#               idempotently write the apt source list → (by default) apt-get update.
# The caller passes the key filename / signed-by path in the vendor's exact format (no arbitrary conversion — it breaks repo auth).
# Per-vendor key-handling differences (downloader flags, dearmor write, list comparison) are preserved via arguments.
#
# Usage:
#   add_apt_repo \
#       --key-file PATH --key-url URL \
#       [--mode raw|dearmor] [--downloader curl|curl-sSf|wget] [--key-write tee|gpg-o] \
#       --list-file PATH \
#       { --list-line "deb ..." | --list-url URL --list-sed "s#..#..#g" } \
#       [--list-cmp grep|cat] [--no-update]
#
#   raw     = store the key as-is (armored .asc / original). Always `sudo curl -fsSL URL -o KEY`.
#   dearmor = `<downloader> URL | gpg --dearmor | sudo tee KEY`  (--key-write tee, default)
#             or `<downloader> URL | sudo gpg --dearmor -o KEY` (--key-write gpg-o)
#   list-cmp grep = single-line grep -qxF (default) / cat = full multi-line comparison (upstream list+sed).

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

    # Downloader (→ stdout) flag array — preserved exactly per vendor.
    local -a dl
    case "${downloader}" in
        curl)     dl=(curl -fsSL);;
        curl-sSf) dl=(curl -sSf);;
        wget)     dl=(wget -qO-);;
        *) echo "add_apt_repo: unknown downloader '${downloader}'" >&2; return 2;;
    esac

    # 1) keyring directory + key (only if absent — idempotent).
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

    # 2) apt source list — do not rewrite if content is identical (prevents duplication/overwrite).
    local desired
    if [[ -n "${list_url}" ]]; then
        # Fetch the upstream list and inject signed-by (sed). Multi-line, so cat comparison is the default.
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

    # 3) refresh the apt cache (skipped if the caller passes --no-update — when a separate update follows repo-add).
    if [[ "${do_update}" == "1" ]]; then
        sudo apt-get update
    fi
}
