#!/usr/bin/bash

set -euo pipefail

fail() {
    echo "${*}" >&2
    exit 1
}

if [[ -z "${GENTOO_REPO}" ]]; then
    fail 'GENTOO_REPO env var empty'
fi

part=$(git log -1 --pretty=format:%s | cut -f 1 -d :)

if [[ "${part}" = 'eclass/'* ]]; then
    part="${part}.eclass"
fi

thisdir=$(dirname "${0}")

swg="${thisdir}/sync-with-gentoo"

GENTOO_REPO="${GENTOO_REPO}" "${swg}" -a "${part}"
