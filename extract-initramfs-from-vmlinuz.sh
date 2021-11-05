#!/bin/bash

# Does as it says on the tin.
#
# Example: extract-initramfs-from-vmlinuz /boot/flatcar/vmlinuz-a out-dir
#
# This will create out-dir/rootfs-0 directory that contains initramfs.

set -euo pipefail
# check for unzstd. Will abort the script with an error message if the tool is not present.
unzstd -V >/dev/null
fail() {
    echo "${*}" >&2
    exit 1
}

# Stolen from extract-vmlinux and modified.
try_decompress() {
    local header="${1}"
    local no_idea="${2}"
    local tool="${3}"
    local image="${4}"
    local tmp="${5}"
    local output_basename="${6}"

    local pos
    local tool_filename=$(echo "${tool}" | cut -f1 -d' ')
    # The obscure use of the "tr" filter is to work around older versions of
    # "grep" that report the byte offset of the line instead of the pattern.

    # Try to find the header and decompress from here.
    for pos in $(tr "${header}\n${no_idea}" "\n${no_idea}=" < "${image}" |
                     grep --text --byte-offset --only-matching "^${no_idea}")
    do
        pos=${pos%%:*}
        # Disable error handling, because we will be potentially
        # giving the tool garbage or a valid archive with some garbage
        # appended to it. So let the tool extract the valid archive
        # and then complain about the garbage at the end, but don't
        # fail the script because of it.
        set +e; tail "-c+${pos}" "${image}" | "${tool}" >"${tmp}/out" 2>/dev/null; set -e;
        if [ -s "${tmp}/out" ]; then
            mv "${tmp}/out" "${output_basename}-${tool_filename}-at-${pos}"
        else
            rm -f "${tmp}/out"
        fi
    done
}

try_unzstd_decompress() {
    local image="${1}"
    local tmp="${2}"
    local output_basename="${3}"
    try_decompress '(\265/\375' xxx unzstd "${image}" "${tmp}" "${output_basename}"
}

me="${0##*/}"
if [[ $# -ne 2 ]]; then
    fail "Usage: ${me} <vmlinuz> <output_directory>"
fi
image="${1}"
out="${2}"
if [[ ! -s "${image}" ]]; then
    fail "The image file '${image}' either does not exist or is empty"
fi
mkdir -p "${out}"

tmp=$(mktemp --directory /tmp/eifv-XXXXXX)
trap "rm -rf ${tmp}" EXIT

tmp_dec="${tmp}/decompress"
mkdir "${tmp_dec}"
fr_prefix="${tmp}/first-round"
try_unzstd_decompress "${image}" "${tmp_dec}" "${fr_prefix}"

shopt -s failglob

rootfs_idx=0
for fr in "${fr_prefix}"*; do
    fr_files="${fr}-files"
    fr_dec="${fr_files}/decompress"
    mkdir -p "${fr_dec}"
    sr_prefix="${fr_files}/second-round"
    try_unzstd_decompress "${fr}" "${fr_dec}" "${sr_prefix}"

    for sr in "${sr_prefix}"*; do
        if [[ $(file --brief "${sr}") =~ 'cpio archive' ]]; then
            sr_files="${sr}-files"
            sr_uccpio="${sr_files}/microcode-cpio-contents"
            mkdir -p "${sr_uccpio}"
            blocks=$(cpio --extract --make-directories --directory="${sr_uccpio}" <"${sr}" 2>&1 | grep --only-matching '[0-9]\+')
            initramfs_cpio="${sr_files}/initramfs.cpio"
            dd if="${sr}" of="${initramfs_cpio}" bs=512 skip="${blocks}" 2>/dev/null
            if [[ $(file --brief "${initramfs_cpio}") =~ 'cpio archive' ]]; then
                rootfs_dir="${out}/rootfs-${rootfs_idx}"
                mkdir -p "${rootfs_dir}"
                cpio --extract --quiet --make-directories --directory="${rootfs_dir}" --nonmatching 'dev/*' <"${initramfs_cpio}"
                rootfs_idx=$((rootfs_idx+1))
            fi
        fi
    done
done

if [[ ${rootfs_idx} -eq 0 ]]; then
    fail "no initramfs found in ${image}"
fi

echo "done, found ${rootfs_idx} rootfs(es)"
