#!/bin/bash

set -euo pipefail

function fail {
    echo "${@}" >&2
    exit 1
}

dbg=false

if [[ $# -gt 0 ]] && [[ "${1}" = '-d' ]]; then
    dbg=true
    shift
fi

if [[ $# -lt 1 ]]; then
    fail "${0} [version [version [version […]]]"
fi

workdir=$(mktemp --directory --tmpdir="$(dirname $0)" gkbi.XXXXXXXXXX)

if ! "${dbg}"; then
    trap "rm -rf ${workdir}" EXIT
fi

gq='--quiet'
if "${dbg}"; then
    gq=''
fi

git -C "${workdir}" clone ${gq} 'https://github.com/kinvolk/manifest.git' 'manifest'

mandir="${workdir}/manifest"

function mgit {
    git -C "${mandir}" "${@}"
}

order=(
    'lts'
    'stable'
    'beta'
    'alpha'
)

declare -A infos

for v in "${@}"; do
    found_order=''
    for o in "${order[@]}"; do
        if [[ -z "${o}" ]]; then
            # the order got "removed" by making it empty
            continue
        fi
        branch_pattern="origin/flatcar-${o}-${v}"'.*'
        all_branches="$(mgit branch --remote --list "${branch_pattern}")"
        if "${dbg}"; then
            echo "branch pattern: ${branch_pattern}"
            echo 'all branches:'
            echo "${all_branches}"
        fi
        latest_version=$(echo "${all_branches}" | \
                             cut -f3 -d- | \
                             sort --version-sort --reverse | \
                             head --lines 1)
        if [[ -z "${latest_version}" ]]; then
            continue
        fi
        found_order="${o}"
        branch="flatcar-${o}-${latest_version}"
        mgit checkout --quiet "${branch}"
        sdk_version=$(cat "${mandir}/version.txt" | grep -e 'FLATCAR_SDK_VERSION\s*=' | cut -f2 -d=)
        infos["${v}"]="sdk: ${sdk_version} , channel base: ${o} , latest version: ${latest_version}"
        break
    done
    if [[ -z "${found_order}" ]]; then
        fail "nothing suitable for ${v} found"
    fi
    order=( "${order[@]/${found_order}}" )
done

for v in "${!infos[@]}"; do
    echo "${v}: ${infos[${v}]}"
done
