#!/bin/bash

# Print a diff of common packages between arm64 and amd64 production
# and container images to see if there are packages that have
# differing versions between the architectures. When such packages
# exist, the script prints the differences between arches and returns
# with an exit status of 1. Otherwise, nothing is printed and the exit
# status is 0.
#
# Example invocations:
# ====================
#
# DEVELOPER=x AMD_VERSION=2022.02.27+dev-main-nightly-4976 ./package-discrepancies.sh
#
# CHANNEL=stable ARM_VERSION=3033.2.0 AMD_VERSION=3033.2.0 ./package-discrepancies.sh
#
# Environment variables:
# ======================
#
# DEVELOPER:
#
# Use developer builds if variable is not empty. Setting this variable
# requires setting AMD_VERSION and ARM_VERSION variables too.
#
# CHANNEL:
#
# Channel to use ("alpha", "beta", "stable", "developer"), defaults to
# "alpha" for non-developer builds. Defaults to "developer" for
# developer builds.
#
# AMD_VERSION:
#
# Version of amd64-usr build to use, defaults to "current" for
# non-developer builds, and to "-" for developer builds. For
# non-developer builds, version looks like "3033.2.2". For developer
# builds, version usually looks like
# "2022.02.25+dev-flatcar-master-4963" or
# "2022.02.26+dev-main-nightly-4971". Version can also be "-" - in
# this case it will copy the version from ARM_VERSION. If ARM_VERSION
# is also "-", then the variables are treated as unspecified (falls
# back to current for non-developer builds, bails out for developer
# builds).
#
# ARM_VERSION:
#
# Version of arm64-usr build to use, defaults to "current" for
# non-developer builds, and to "-" for developer builds. For
# non-developer builds, version looks like "3033.2.2". For developer
# builds, version usually looks like
# "2022.02.25+dev-flatcar-master-4963" or
# "2022.02.26+dev-main-nightly-4971". Version can also be "-" - in
# this case it will copy the version from AMD_VERSION. If AMD_VERSION
# is also "-", then the variables are treated as unspecified (falls
# back to current for non-developer builds, bails out for developer
# builds).
#
# Environment variables used for debugging:
# =========================================
#
# WORKDIR:
#
# A path to a working directory that will hold temporary files.
#
# KEEP_WORKDIR:
#
# If specified to non-empty value, then the workdir will be printed to
# standard error and will not be removed after script finishes.

set -euo pipefail

this_dir="$(dirname "${0}")"

: ${DEVELOPER:=}

if [[ -z "${DEVELOPER}" ]]; then
    : ${CHANNEL:='alpha'}
    : ${AMD_VERSION:='current'}
    : ${ARM_VERSION:='current'}
else
    : ${CHANNEL:='developer'}
    : ${AMD_VERSION:='-'}
    : ${ARM_VERSION:='-'}
fi

if [[ "${AMD_VERSION}" = '-' ]]; then
    AMD_VERSION="${ARM_VERSION}"
fi
if [[ "${ARM_VERSION}" = '-' ]]; then
    ARM_VERSION="${AMD_VERSION}"
fi

if [[ -z "${DEVELOPER}" ]]; then
    if [[ "${AMD_VERSION}" = '-' ]]; then
        AMD_VERSION='current'
    fi
    if [[ "${ARM_VERSION}" = '-' ]]; then
        ARM_VERSION='current'
    fi
else
    if [[ "${AMD_VERSION}" = '-' ]]; then
        echo 'Unspecified AMD64 image version' >&2
        exit 1
    fi
    if [[ "${ARM_VERSION}" = '-' ]]; then
        echo 'Unspecified ARM64 image version' >&2
        exit 1
    fi
fi

: ${WORKDIR:="${this_dir}/$(mktemp --directory 'pd.XXXXXXXXXX')"}
: ${KEEP_WORKDIR:=}

if [[ -z "${DEVELOPER}" ]]; then
    main_url="https://${CHANNEL}.release.flatcar-linux.net"
else
    main_url="https://bucket.release.flatcar-linux.net/flatcar-jenkins/developer/${CHANNEL}/boards"
fi

amd_part="amd64-usr/${AMD_VERSION}"
arm_part="arm64-usr/${ARM_VERSION}"
amd_url="${main_url}/${amd_part}"
arm_url="${main_url}/${arm_part}"
amd_container_pkgs_url="${amd_url}/flatcar_developer_container_packages.txt"
amd_image_pkgs_url="${amd_url}/flatcar_production_image_packages.txt"
arm_container_pkgs_url="${arm_url}/flatcar_developer_container_packages.txt"
arm_image_pkgs_url="${arm_url}/flatcar_production_image_packages.txt"

mkdir -p "${WORKDIR}"

if [[ -z "${KEEP_WORKDIR}" ]]; then
    trap "rm -rf '${WORKDIR}'" EXIT
else
    echo "WORKDIR='${WORKDIR}'" >&2
fi

ARCHES=('amd' 'arm')
KINDS=('container' 'image')

download() {
    local url="${1}"
    local output="${2}"

    curl \
        --location \
        --silent \
        --show-error \
        --output "${output}" \
        "${url}"
}

download_action() {
    local kind="${1}"
    local arch="${2}"

    local url_var="${arch}_${kind}_pkgs_url"
    local out="${WORKDIR}/${arch}_${kind}_pkgs"
    download "${!url_var}" "${out}"
}

for_each_kind_arch() {
    local action="${1}"
    for kind in "${KINDS[@]}"; do
        for arch in "${ARCHES[@]}"; do
            "${action}" "${kind}" "${arch}"
        done
    done
}

download_package_files() {
    if [[ -e "${WORKDIR}/amd_container_pkgs" ]] && \
           [[ -e "${WORKDIR}/amd_image_pkgs" ]] && \
           [[ -e "${WORKDIR}/arm_container_pkgs" ]] && \
           [[ -e "${WORKDIR}/arm_image_pkgs" ]]; then
        return
    fi
    for_each_kind_arch download_action
}

drop_src_action() {
    local kind="${1}"
    local arch="${2}"

    local file="${WORKDIR}/${arch}_${kind}_pkgs"
    local file_dsrc="${file}_dsrc"

    sed -e 's/::.*//' "${file}" >"${file_dsrc}"
}

drop_src() {
    if [[ -e "${WORKDIR}/amd_image_pkgs_dsrc" ]] && \
           [[ -e "${WORKDIR}/amd_container_pkgs_dsrc" ]] && \
           [[ -e "${WORKDIR}/arm_image_pkgs_dsrc" ]] && \
           [[ -e "${WORKDIR}/arm_container_pkgs_dsrc" ]]; then
        return
    fi
    download_package_files
    for_each_kind_arch drop_src_action
}

merge_pkgs() {
    if [[ -e "${WORKDIR}/amd_pkgs" ]] && \
           [[ -e "${WORKDIR}/arm_pkgs" ]]; then
        return
    fi
    drop_src

    local arch
    for arch in "${ARCHES[@]}"; do
        LC_ALL=C sort --unique "${WORKDIR}/${arch}_"{image,container}'_pkgs_dsrc' >"${WORKDIR}/${arch}_pkgs"
    done
}

get_pkg_names() {
    if [[ -e "${WORKDIR}/amd_pkg_names" ]] && \
           [[ -e "${WORKDIR}/arm_pkg_names" ]]; then
        return
    fi
    merge_pkgs
    local arch
    for arch in "${ARCHES[@]}"; do
        sed -e 's/-[0-9]\+\(\.[0-9]\+\)*.*//' "${WORKDIR}/${arch}_pkgs" >"${WORKDIR}/${arch}_pkg_names"
    done
}

get_common_pkg_names() {
    if [[ -e "${WORKDIR}/common_pkg_names" ]]; then
        return
    fi
    get_pkg_names
    LC_ALL=C comm -1 -2 "${WORKDIR}/"{amd,arm}'_pkg_names' >"${WORKDIR}/common_pkg_names"
}

# lines in the input stream must be sorted
#
# passed parameters must be sorted
filter_pkgs() {
    local pkg_name
    local line
    while [[ "${#}" -gt 0 ]] && read -r line; do
        pkg_name="${1}"
        if [[ "${line}" == "${pkg_name}-"* ]]; then
            printf '%s\n' "${line}"
            shift
        fi
    done
}

filter_common_pkgs() {
    if [[ -e "${WORKDIR}/amd_filtered_pkgs" ]] && \
           [[ -e "${WORKDIR}/arm_filtered_pkgs" ]]; then
        return
    fi
    get_common_pkg_names
    local line
    local -a all_common_pkgs
    while read -r line; do
        all_common_pkgs+=("${line}")
    done <"${WORKDIR}/common_pkg_names"
    merge_pkgs
    local arch
    for arch in "${ARCHES[@]}"; do
        filter_pkgs "${all_common_pkgs[@]}" <"${WORKDIR}/${arch}_pkgs" >"${WORKDIR}/${arch}_filtered_pkgs"
    done
}

get_diff() {
    if [[ -e "${WORKDIR}/diff_output" ]]; then
        return
    fi
    filter_common_pkgs
    { diff -u "${WORKDIR}/"{amd,arm}'_filtered_pkgs' || :; } >"${WORKDIR}/diff_output"
}

get_diff
if [[ -s "${WORKDIR}/diff_output" ]]; then
    cat "${WORKDIR}/diff_output"
    exit 1
fi

exit 0
