#!/usr/bin/bash

set -euo pipefail

function msg {
    echo "download-test-results.sh: ${*}"
}

function msgn {
    echo -n "download-test-results.sh: ${*}"
}

function fail {
    msg "${*}" >&2
    exit 1
}


if [[ ${#} -lt 2 ]]; then
    fail "Need at least two parameters, a test directory URL and at least one machine name (usually some UUID)"
fi

URL="${1}"; shift
FILES=(
    'console.txt'
    'ignition.json'
    'journal-raw.txt.gz'
    'journal.txt'
)

for m in "${@}"; do
    mkdir "${m}"
    pushd "${m}" >/dev/null
    msg "Downloading files for '${m}'."
    for f in "${FILES[@]}"; do
        msgn "  Downlading '${f}'… "
        if wget --quiet "${URL}/${m}/${f}"; then
            echo "ok."
        else
            STATUS=$?
            echo "failed."
            msg "    Exit status: ${STATUS}"
        fi
    done
    popd >/dev/null
done
