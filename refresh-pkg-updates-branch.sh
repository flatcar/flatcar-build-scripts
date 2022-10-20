#!/usr/bin/bash

set -euo pipefail

: ${GENTOO_REPO:=}
: ${BASE:=origin/main}

fail() {
    echo "refresh-pkg-updates-branch: ${*}" >&2
    exit 1
}

if [[ -z "${GENTOO_REPO}" ]]; then
    fail 'GENTOO_REPO env var empty'
fi

if [[ -z "${BASE}" ]]; then
    fail 'BASE env var empty'
fi

thisdir=$(realpath $(dirname "${0}"))
helper="${thisdir}/rpub-rebase-helper.sh"
snippet="GENTOO_REPO='${GENTOO_REPO}' '${helper}'"

git rebase --exec "${snippet}" "${BASE}"
