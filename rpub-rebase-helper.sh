#!/usr/bin/bash

set -euo pipefail

# this is to visually separate each helper invocation
trap 'echo' EXIT

fail() {
    echo "rpub-rebase-helper: ${*}" >&2
    exit 1
}

if [[ -z "${GENTOO_REPO}" ]]; then
    fail 'GENTOO_REPO env var empty'
fi

commit=$(git log -1 --pretty=format:%s)

echo "rpub-rebase-helper: Commit: '${commit}'"

part=$(cut -f 1 -d : <<<"${commit}")
rest=$(cut -f 2- -d : <<<"${commit}")
pattern='[Ss]ync with [gG]entoo|[Aa]dd from [Gg]entoo'

if [[ ! "${rest}" =~ ${pattern} ]]; then
    echo 'rpub-rebase-helper: Not a commit to sync'
    exit 0
fi
if [[ "${part}" = 'eclass/'* ]]; then
    part="${part}.eclass"
fi

thisdir=$(dirname "${0}")

swg="${thisdir}/sync-with-gentoo"

GENTOO_REPO="${GENTOO_REPO}" "${swg}" -a "${part}"
