#!/bin/bash

###
### size change reporter
###
### Downloads image contents listing files, compares them and prints a
### report about largest new files added and removed, and about largest
### increases and decreases in modified files.
###
### Usage:
###
### size-change-report.sh [options] <spec_a> <spec_b>
###
### spec is a string in one of three forms:
### release:<channel>:<board>:<version>:<kind> (e.g. release:alpha:amd64-usr:3480.0.0:old)
### bincache:<arch>:<version>:<kind> (e.g. bincache:amd64:3483.0.0+weekly-updates-11:wtd)
### local:<dirpath>:<kind>
###
### channel: alpha, beta, stable, lts
### board: amd64-usr, arm64-usr
### kind: old, wtd, initrd-old, initrd-wtd, oem-${OEM}-old, oem-${OEM}-wtd,
###       base-sysext-${NAME}-old base-sysext-${NAME}-wtd
###       extra-sysext-${NAME}-old extra-sysext-${NAME}-wtd
### arch: amd64, arm64
###
### options:
### (limit options default to 10, limit is disabled if it is 0 or less)
### -n <num> - limit newly added files listing to <num>
### -d <num> - limit deleted files listing to <num>
### -g <num> - limit grown files listing to <num>
### -s <num> - limit shrunk files listing to <num>
### -h - this help
###
### env vars:
### WORKDIR - where work files are downloaded/generated, defaults to a temporary directory
### KEEP_WORKDIR - if not empty, do not delete the workdir, defaults to empty
###

set -euo pipefail

function fail {
    printf '%s\n' "${*}" >&2
    exit 1
}

NEW_LIMIT=10
DELETED_LIMIT=10
GROWN_LIMIT=10
SHRUNK_LIMIT=10

spec_a=
spec_b=

while [[ ${#} -gt 0 ]]; do
    case "${1}" in
        -n)
            # shellcheck disable=SC2034 # Used through indirection
            NEW_LIMIT="${2}";
            shift
            ;;
        -d)
            # shellcheck disable=SC2034 # Used through indirection
            DELETED_LIMIT="${2}";
            shift
            ;;
        -g)
            # shellcheck disable=SC2034 # Used through indirection
            GROWN_LIMIT="${2}";
            shift
            ;;
        -s)
            # shellcheck disable=SC2034 # Used through indirection
            SHRUNK_LIMIT="${2}";
            shift
            ;;
        -h)
            grep '^###' "${0}" | sed -e 's/^###.\?//'
            exit 0
            ;;
        -*)
            fail "Unknown flag '${1}'"
            ;;
        *)
            if [[ -z "${spec_a}" ]]; then
                spec_a="${1}"
            elif [[ -z "${spec_b}" ]]; then
                spec_b="${1}"
            else
                fail 'Two specs are enough'
            fi
            ;;
    esac
    shift
done

function file_from_kind {
    local spec="${1}"; shift
    local kind="${1}"; shift
    local oemid name
    case "${kind}" in
        old)
            echo 'flatcar_production_image_contents.txt'
            ;;
        wtd)
            echo 'flatcar_production_image_contents_wtd.txt'
            ;;
        initrd-old)
            echo 'flatcar_production_image_initrd_contents.txt'
            ;;
        initrd-wtd)
            echo 'flatcar_production_image_initrd_contents_wtd.txt'
            ;;
        realinitrd-wtd)
            echo 'flatcar_production_image_realinitrd_contents_wtd.txt'
            ;;
        oem-*-old)
            oemid=${kind}
            oemid=${oemid#oem-}
            oemid=${oemid%-old}
            echo "oem-${oemid}_contents.txt"
            ;;
        oem-*-wtd)
            oemid=${kind}
            oemid=${oemid#oem-}
            oemid=${oemid%-wtd}
            echo "oem-${oemid}_contents_wtd.txt"
            ;;
        base-sysext-*-old)
            name=${kind}
            name=${name#base-sysext-}
            name=${name%-old}
            echo "rootfs-included-sysexts/${name}_contents.txt"
            ;;
        base-sysext-*-wtd)
            name=${kind}
            name=${name#base-sysext-}
            name=${name%-wtd}
            echo "rootfs-included-sysexts/${name}_contents_wtd.txt"
            ;;
        extra-sysext-*-old)
            name=${kind}
            name=${name#extra-sysext-}
            name=${name%-old}
            echo "flatcar-${name}_contents.txt"
            ;;
        extra-sysext-*-wtd)
            name=${kind}
            name=${name#extra-sysext-}
            name=${name%-wtd}
            echo "flatcar-${name}_contents_wtd.txt"
            ;;
        *)
            fail "Invalid kind '${kind}' in spec '${spec}', see help for possible values"
            ;;
    esac
}

# spec can be:
#
# release:CHANNEL:BOARD:VERSION:KIND
# bincache:ARCH:VERSION:KIND
# local:DIRPATH:KIND
function handle_spec {
    local spec="${1}"; shift
    local output="${1}"; shift
    local output_kind="${1}"; shift

    if [[ $(wc -l <<<"${spec}") -ne 1 ]]; then
        fail "Invalid spec '${spec}', can't be multiline"
    fi

    local -a spec_ar url

    mapfile -t spec_ar < <(tr ':' '\n' <<<"${spec}")

    case "${spec_ar[0]}" in
        release)
            if [[ "${#spec_ar[@]}" -ne 5 ]]; then
                fail "Invalid release spec '${spec}', should be in form of release:CHANNEL:BOARD:VERSION:KIND"
            fi
            local channel board version kind file
            channel="${spec_ar[1]}"
            board="${spec_ar[2]}"
            version="${spec_ar[3]}"
            kind="${spec_ar[4]}"
            url="https://${channel}.release.flatcar-linux.net/${board}/${version}"
            file=$(file_from_kind "${spec}" "${kind}")
            curl --location --silent -S -o "${output}" "${url}/${file}"
            echo "${kind}" >"${output_kind}"
            ;;
        bincache)
            if [[ "${#spec_ar[@]}" -ne 4 ]]; then
                fail "Invalid bincache spec '${spec}', should be in form of bincache:ARCH:VERSION:KIND"
            fi
            local arch version kind file
            arch="${spec_ar[1]}"
            version="${spec_ar[2]}"
            kind="${spec_ar[3]}"
            url="https://bincache.flatcar-linux.net/images/${arch}/${version}"
            file=$(file_from_kind "${spec}" "${kind}")
            curl --location --silent -S -o "${output}" "${url}/${file}"
            echo "${kind}" >"${output_kind}"
            ;;
        local)
            if [[ "${#spec_ar[@]}" -ne 3 ]]; then
                fail "Invalid file spec '${spec}', should be in form of local:DIRPATH:KIND"
            fi
            local path kind file
            dirpath="${spec_ar[1]}"
            kind="${spec_ar[2]}"
            file=$(file_from_kind "${spec}" "${kind}")
            cp -a "${dirpath%/}/${file}" "${output}"
            echo "${kind}" >"${output_kind}"
            ;;
        *)
            fail "Invalid spec '${spec}', should have either release, bincache or file in the first field"
            ;;
    esac
    if [[ ! -s "${output}" ]]; then
        fail "Failed to get the listing for spec ${spec}"
    fi
}

: "${WORKDIR:=}"
: "${KEEP_WORKDIR:=}"

if [[ -z "${WORKDIR}" ]]; then
    WORKDIR=$(mktemp --tmpdir --directory "scr-XXXXXXXX")
    # print workdir only if we are going to keep it
    if [[ -n ${KEEP_WORKDIR} ]]; then
        echo "Workdir in ${WORKDIR}"
    fi
fi

mkdir -p "${WORKDIR}"

if [[ -z ${KEEP_WORKDIR} ]]; then
    # shellcheck disable=SC2064 # WORKDIR won't change, so we can expand it now.
    trap "rm -rf '${WORKDIR}'" EXIT
fi

wd="${WORKDIR}"

function any_missing {
    local file

    for file; do
        if [[ ! -e "${file}" ]]; then
            return 0
        fi
    done
    return 1
}

if any_missing "${wd}/A" "${wd}/B" "${wd}/kind-of-A" "${wd}/kind-of-B"; then
    echo "Downloading file listings"
    handle_spec "${spec_a}" "${wd}/A" "${wd}/kind-of-A"
    handle_spec "${spec_b}" "${wd}/B" "${wd}/kind-of-B"
    if [[ "$(cat "${wd}/kind-of-A")" != "$(cat "${wd}/kind-of-B")" ]]; then
        fail "Can't compare between different kind of files"
    fi
fi

function xgrep {
    grep "${@}" || :
}

function xawk {
    awk "${@}" || :
}

function xgit {
    git "${@}" || :
}

function xsort {
    sort "${@}" 2>/dev/null || :
}

function file_lineno {
    wc -l "${1}" | cut -d' ' -f1
}

function simplified_kind {
    local path="${1}"
    local kind

    kind=$(cat "${path}")

    case "${kind}" in
        old|wtd)
            :
            ;;
        initrd-old|initrd-wtd)
            kind="${kind#initrd-}"
            ;;
        realinitrd-wtd)
            kind="${kind#realinitrd-}"
            ;;
        oem-*-old|oem-*-wtd|base-sysext-*-old|base-sysext-*-wtd|extra-sysext-*-old|extra-sysext-*-wtd)
            kind=${kind##*-}
            ;;
        *)
            fail "Unexpected kind '${kind}' passed through initial checks."
            ;;
    esac

    echo "${kind}"
}

if any_missing "${wd}/output" "${wd}/detailed_output" "${wd}/for_cache_key_cache"; then
    echo "Generating file listing diffs"
    kind=$(simplified_kind "${wd}/kind-of-A")
    for f in "${wd}/A" "${wd}/B"; do
        if [[ "${kind}" = 'old' ]]; then
            # Cut date and time noise away
            sed -e 's/....-..-.. ..:.. //g' "${f}" >"${f}.1.no-date-time"
        else
            cp -a "${f}" "${f}.1.no-date-time"
        fi
        # Sort by path
        xsort -t / -k 2 "${f}.1.no-date-time" >"${f}.2.sorted"
        # Drop directories and symlinks
        xgrep -v '^[dl]' "${f}.2.sorted" > "${f}.3.files-only"

        # Keep paths only
        cut -d . -f 2- "${f}.3.files-only" > "${f}.4a.paths-only"
        # Simplify dot-separated sequences of numbers to a single zero (that also handles kernel versions)
        sed -E 's/[0-9]+(\.[0-9]+)*/0/g' "${f}.4a.paths-only" >"${f}.5a.no-numbers"
        # Skip SLSA stuff
        xgrep -v /usr/share/SLSA/ "${f}.5a.no-numbers" >"${f}.6a.no-slsa"

        # Simplify kernel versions to just a.b.c
        sed -E 's#[0-9]+\.[0-9]+\.[0-9]+-flatcar#a.b.c-flatcar#g' "${f}.3.files-only" >"${f}.4b.cut-kernel"
        # Drop unnecessary parts (permissions, user and group information)
        if [[ "${kind}" = 'old' ]]; then
            # Keep only hardlink count, size and path
            xawk '{ print $2 " " $5 " " $6 }' "${f}.4b.cut-kernel" >"${f}.5b.needed-parts-only"
        else
            # Keep only device ID, inode, hardlink count, size and path
            xawk '{ print $2 " " $3 " " $4 " " $5 " " $6 }' "${f}.4b.cut-kernel" >"${f}.5b.needed-parts-only"
        fi
        # Generate a single form with lines having cache key, hardlink count, size and path info only
        if [[ "${kind}" = 'old' ]]; then
            # Cache key will be made from hardlink count and size
            # 1 - hardlink count
            # 2 - size
            # 3 - path
            xawk '{ print $1 "-" $2 " " $1 " " $2 " " $3 }' "${f}.5b.needed-parts-only" >"${f}.6b.single-form"
        else
            # Cache key will be made from device ID and inode
            # 1 - device ID
            # 2 - inode
            # 3 - hardlink count
            # 4 - size
            # 5 - path
            xawk '{ print $1 "-" $2 " " $3 " " $4 " " $5 }' "${f}.5b.needed-parts-only" >"${f}.6b.single-form"
        fi
        # Generate a final form without cache key for smaller diffs
        # (so, only hardlink count, size and path info).
        xawk '{ print $2 " " $3 " " $4 }' "${f}.6b.single-form" >"${f}.7ba.final-form-no-cache-key"

        # Generate a file with lines having cache key and path only.
        xawk '{ print $1 " " $4 }' "${f}.6b.single-form" >"${f}.7bb.final-form-only-cache-key"
    done

    # Generate simple output, without the diff noise. File format:
    # <diff sign><simplified path>
    xgit diff \
        --no-index \
        -- \
        "${wd}/A.6a.no-slsa" "${wd}/B.6a.no-slsa" | \
        tail --lines +6 | \
        xgrep -v '^@' >"${wd}/output"

    # use a ginormous amount of context to capture all the unmodified
    # files, will be needed for hardlink hunting
    lineno_a=$(file_lineno "${wd}/A.7ba.final-form-no-cache-key")
    lineno_b=$(file_lineno "${wd}/B.7ba.final-form-no-cache-key")
    lineno=${lineno_a}
    if [[ ${lineno} -lt ${lineno_b} ]]; then
        lineno=${lineno_b}
    fi
    # Generate detailed output, without the diff noise and cache keys. File format;
    # <diff sign><hardlink count> <size> <path>
    if git diff \
           --unified="${lineno}" \
           --no-index \
           -- \
           "${wd}/A.7ba.final-form-no-cache-key" "${wd}/B.7ba.final-form-no-cache-key" | \
            tail --lines +6; then
        # If both files are the same, diff will show no output. In
        # such case, print one of the files prepending an empty space
        # (meaning no change in diffesque).
        sed -e 's/^/ /' "${wd}/A.7ba.final-form-no-cache-key"
    fi >"${wd}/detailed_output"
    # Generate detailed output, without the diff noise, size and hardlink info. File format;
    # <diff sign><cache key> <path>
    if git diff \
           --unified="${lineno}" \
           --no-index \
           -- \
           "${wd}/A.7bb.final-form-only-cache-key" "${wd}/B.7bb.final-form-only-cache-key" | \
            tail --lines +6; then
        # If both files are the same, diff will show no output. In
        # such case, print one of the files prepending an empty space
        # (meaning no change in diffesque).
        sed -e 's/^/ /' "${wd}/A.7bb.final-form-only-cache-key"
    fi >"${wd}/for_cache_key_cache"
fi

#
# cache key cache
#

declare -A plus_key_cache
declare -A space_key_cache
declare -A minus_key_cache
plus_key_cache=()
space_key_cache=()
minus_key_cache=()

cache_key_cache_prepared=

function fill_cache_key_caches {
    if [[ -n "${cache_key_cache_prepared}" ]]; then
        return 0
    fi
    echo "Filling cache key caches"
    local diff_cache_key path cache_key
    while read -r diff_cache_key path; do
        cache_key="${diff_cache_key#[-+ ]}"
        case "${diff_cache_key}" in
            +)
                plus_key_cache[${path}]="${cache_key}"
                ;;
            -)
                minus_key_cache[${path}]="${cache_key}"
                ;;
            *)
                space_key_cache[${path}]="${cache_key}"
                ;;
        esac
    done <"${wd}/for_cache_key_cache"
    cache_key_cache_prepared=x
}

function get_old_cache_key {
    local path="${1}"; shift
    local gock_cache_key_var_name="${1}"; shift
    local -n gock_cache_key_var_ref="${gock_cache_key_var_name}"

    gock_cache_key_var_ref="${minus_key_cache[${path}]:-}"
    if [[ -z "${gock_cache_key_var_ref}" ]]; then
        gock_cache_key_var_ref="${space_key_cache[${path}]:-}"
        if [[ -z "${gock_cache_key_var_ref}" ]]; then
            echo "NO OLD CACHE KEY FOUND FOR '${path}', EXPECT A BAD REPORT!"
        fi
    fi
}

function get_new_cache_key {
    local path="${1}"; shift
    local gnck_cache_key_var_name="${1}"; shift
    local -n gnck_cache_key_var_ref="${gnck_cache_key_var_name}"

    gnck_cache_key_var_ref="${plus_key_cache[${path}]:-}"
    if [[ -z "${gnck_cache_key_var_ref}" ]]; then
        gnck_cache_key_var_ref="${space_key_cache[${path}]:-}"
        if [[ -z "${gnck_cache_key_var_ref}" ]]; then
            echo "NO NEW CACHE KEY FOUND FOR '${path}', EXPECT A BAD REPORT!"
        fi
    fi
}

function get_unchanged_cache_key {
    local path="${1}"; shift
    local guck_cache_key_var_name="${1}"; shift
    local -n guck_cache_key_var_ref="${guck_cache_key_var_name}"

    guck_cache_key_var_ref="${space_key_cache[${path}]:-}"
    if [[ -z "${guck_cache_key_var_ref}" ]]; then
        echo "NO UNCHANGED CACHE KEY FOUND FOR '${path}', EXPECT A BAD REPORT!"
    fi
}

#
# categorize stuff into new, deleted, changed and unchanged
#
# CK - cache key
# HLC - hardlink count
#
# line format of new, deleted, unchanged:
# <CK>:<HLC>:<size>:<path>
#
# line format of changed:
# <old CK>:<new CK>:<old HLC>:<new HLC>:<old size>:<new size>:<old_path>@_^_@_^_@<new_path>
#

PATH_SEP='@_^_@_^_@'

function munge_path_into_regexp {
    local path="${1}"; shift
    local regexp="${path}"

    # escape special stuff, means . * $ ^ [
    regexp="${regexp//./\\.}"
    regexp="${regexp//\*/\\\*}"
    regexp="${regexp//^/\\^}"
    regexp="${regexp//$/\\$}"
    regexp="${regexp//[/\\[}"

    printf '%s\n' "${regexp}"
}

function munge_numbers_into_regexps {
    local regexp="${1}"; shift

    # turn all dot separated numbers into a regexp matching dot separated numbers
    sed -E 's/[0-9]+(\.[0-9]+)*/[0-9]\\+\\(\\.[0-9]\\+\\)*/g' <<<"${regexp}"
}

# new
if any_missing "${wd}/new_entries"; then
    fill_cache_key_caches
    echo "Generating new entries"
    new_entries=()
    mapfile -t new_entries < <(xgrep -e '^+/' "${wd}/output" | sed -e 's/^+//')

    truncate --size 0 "${wd}/new_entries"
    for new_entry in "${new_entries[@]}"; do
        regexp=$(munge_path_into_regexp "${new_entry}")
        regexp=$(munge_numbers_into_regexps "${regexp}")
        regexp='^+.* \.'"${regexp}"'$'
        fields=()
        while read -r -a fields; do
            # strip diff sign from first field
            hardlink="${fields[0]#[-+ ]}"
            size="${fields[1]}"
            path="${fields[2]}"
            get_new_cache_key "${path}" cache_key
            printf '%s:%s:%s:%s\n' "${cache_key}" "${hardlink}" "${size}" "${path}" >>"${wd}/new_entries"
        done < <(xgrep -e "${regexp}" "${wd}/detailed_output")
    done
    unset new_entries fields
fi

# deleted
if any_missing "${wd}/deleted_entries"; then
    fill_cache_key_caches
    echo "Generating deleted entries"
    deleted_entries=()
    mapfile -t deleted_entries < <(xgrep -e '^-/' "${wd}/output" | sed -e 's/^-//')

    truncate --size 0 "${wd}/deleted_entries"
    for deleted_entry in "${deleted_entries[@]}"; do
        regexp=$(munge_path_into_regexp "${deleted_entry}")
        regexp=$(munge_numbers_into_regexps "${regexp}")
        regexp='^-.* \.'"${regexp}"'$'
        fields=()
        while read -r -a fields; do
            # strip diff sign from first field
            hardlink="${fields[0]#[-+ ]}"
            size="${fields[1]}"
            path="${fields[2]}"
            get_old_cache_key "${path}" cache_key
            printf '%s:%s:%s:%s\n' "${cache_key}" "${hardlink}" "${size}" "${path}" >>"${wd}/deleted_entries"
        done < <(xgrep -e "${regexp}" "${wd}/detailed_output")
    done
    unset deleted_entries fields
fi

function munge_so_numbers_into_regexps {
    local regexp="${1}"; shift
    local regexp_pre_so regexp_post_so

    # handle so versions specially, pre .so. part will receive a
    # different number matching than the post .so. part
    if [[ "${regexp}" = *'\.so\.'* ]]; then
        regexp_pre_so="${regexp%%\\.so\\.*}"
        regexp_pre_so=$(munge_numbers_into_regexps "${regexp_pre_so}")
        regexp_post_so="${regexp#*\\.so\\.}"
        # turn every number into a regexp matching any number
        regexp_post_so="$(sed -E 's/[0-9]+/[0-9]\\+/g' <<<"${regexp_post_so}")"
        regexp="${regexp_pre_so}"'\.so\.'"${regexp_post_so}"
        printf '%s\n' "${regexp}"
    else
        munge_numbers_into_regexps "${regexp}"
    fi
}

# changed
if any_missing "${wd}/changed_entries"; then
    fill_cache_key_caches
    echo "Generating changed entries"
    # get only added/removed lines and strip the diff sign
    xgrep '^+' "${wd}/detailed_output" | sed -e 's/^.//' >"${wd}/diff-plus-only"
    xgrep '^-' "${wd}/detailed_output" | sed -e 's/^.//' >"${wd}/diff-minus-only"

    truncate --size 0 "${wd}/changed_entries"
    fields=()
    while read -r -a fields; do
        old_hardlink="${fields[0]}"
        old_size="${fields[1]}"
        old_path="${fields[2]}"
        regexp=$(munge_path_into_regexp "${old_path}")
        regexp=$(munge_so_numbers_into_regexps "${regexp}")
        regexp='^.* '"${regexp}"'$'
        results=()
        mapfile -t results < <(xgrep -e "${regexp}" "${wd}/diff-plus-only")
        if [[ ${#results[@]} -eq 0 ]]; then
            continue
        elif [[ ${#results[@]} -gt 1 ]]; then
            found=
            # 1. try the same path
            regexp2=$(munge_path_into_regexp "${old_path}")
            regexp2='^.* '"${regexp2}"'$'
            results2=()
            mapfile -t results2 < <(printf '%s\n' "${results[@]}" | xgrep -e "${regexp2}")
            if [[ ${#results2[@]} -gt 0 ]]; then
                results=( "${results2[0]}" )
                found=x
            fi
            if [[ -z "${found}" ]]; then
                # 2. try the same directory with number-munged basename
                regexp2_dir_part=$(munge_path_into_regexp "$(dirname "${old_path}")")
                regexp2_base_part=$(munge_path_into_regexp "$(basename "${old_path}")")
                regexp2_base_part=$(munge_so_numbers_into_regexps "${regexp2_base_part}")
                regexp2="${regexp2_dir_part}/${regexp2_base_part}"
                regexp2='^.* '"${regexp2}"'$'
                results2=()
                mapfile -t results2 < <(printf '%s\n' "${results[@]}" | xgrep -e "${regexp2}")
                if [[ ${#results2[@]} -gt 0 ]]; then
                    results=( "${results2[0]}" )
                    found=x
                fi
            fi
            if [[ -z "${found}" ]]; then
                # 3. try number-munged directory with the same basename
                regexp2_dir_part=$(munge_path_into_regexp "$(dirname "${old_path}")")
                regexp2_dir_part=$(munge_numbers_into_regexps "${regexp2_dir_part}")
                regexp2_base_part=$(munge_path_into_regexp "$(basename "${old_path}")")
                regexp2="${regexp2_dir_part}/${regexp2_base_part}"
                regexp2='^.* '"${regexp2}"'$'
                results2=()
                mapfile -t results2 < <(printf '%s\n' "${results[@]}" | xgrep -e "${regexp2}")
                if [[ ${#results2[@]} -gt 0 ]]; then
                    results=( "${results2[0]}" )
                    found=x
                fi
            fi
        fi
        read -r -a fields <<<"${results[0]}"
        new_hardlink="${fields[0]}"
        new_size="${fields[1]}"
        new_path="${fields[2]}"
        get_old_cache_key "${old_path}" old_cache_key
        get_new_cache_key "${new_path}" new_cache_key
        # shellcheck disable=SC2154 # old_cache_key and new_cache_key are assigned indirectly just above
        printf '%s:%s:%s:%s:%s:%s:%s%s%s\n' "${old_cache_key}" "${new_cache_key}" "${old_hardlink}" "${new_hardlink}" "${old_size}" "${new_size}" "${old_path}" "${PATH_SEP}" "${new_path}" >>"${wd}/changed_entries"
    done <"${wd}/diff-minus-only"
    unset results results2 fields
fi

# unchanged
if any_missing "${wd}/unchanged_entries"; then
    fill_cache_key_caches
    echo "Generating unchanged entries"
    fields=()
    truncate --size 0 "${wd}/unchanged_entries"
    while read -r -a fields; do
        # strip diff sign from first field
        hardlink="${fields[0]#[-+ ]}"
        size="${fields[1]}"
        path="${fields[2]}"
        get_unchanged_cache_key "${path}" cache_key
        printf '%s:%s:%s:%s\n' "${cache_key}" "${hardlink}" "${size}" "${path}" >>"${wd}/unchanged_entries_nck"
    done < <(xgrep -e '^ ' "${wd}/detailed_output")
    unset fields
fi

#
# field helpers
#

# removes first n fields from tuple
function strip_n {
    local tuple="${1}"; shift
    local sep="${1}"; shift
    local count="${1}"; shift
    local out_var_name="${1}"; shift

    local -n out_var="${out_var_name}"

    local stripped="${tuple}"
    while [[ ${count} -gt 0 ]]; do
        stripped="${stripped#*"${sep}"}"
        count=$((count - 1))
    done
    out_var="${stripped}"
}

# get nth field in tuple
function get_nth {
    local tuple="${1}"; shift
    local sep="${1}"; shift
    local idx="${1}"; shift
    local out_var_name="${1}"; shift

    local -n out_var="${out_var_name}"

    local gn_tmp_v
    strip_n "${tuple}" "${sep}" "${idx}" gn_tmp_v
    # shellcheck disable=SC2034 # out_var is a reference to another variable
    out_var="${gn_tmp_v%%"${sep}"*}"
}

function strip_n_c {
    strip_n "${1}" : "${2}" "${3}"
}

function get_nth_c {
    get_nth "${1}" : "${2}" "${3}"
}

function strip_n_p {
    strip_n "${1}" "${PATH_SEP}" "${2}" "${3}"
}

function get_nth_p {
    get_nth "${1}" "${PATH_SEP}" "${2}" "${3}"
}

#
# hardlink cache
#
# fill it with data from unchanged files, whatever hardlink was added
# or removed, it won't affect final size (that much)
#

# used for ignoring hardlinks
declare -A hls_cache
hls_cache=()
declare -A hls_cache_initial
hls_cache_initial=()
hls_cache_filled=

function update_hls_cache {
    local hardlink="${1}"; shift
    local key="${1}"; shift

    if [[ ${hardlink} -eq 1 ]]; then
        return 0
    fi
    if [[ -n "${hls_cache[${key}]+isset}" ]]; then
        return 1
    fi
    hls_cache[${key}]=x
    return 0
}

function mark_hls_cache_as_initial {
    local key

    hls_cache_initial=()
    for key in "${!hls_cache[@]}"; do
        hls_cache_initial[${key}]=${hls_cache[${key}]}
    done
}

function restore_hls_cache {
    local key

    hls_cache=()
    for key in "${!hls_cache_initial[@]}"; do
        hls_cache[${key}]=${hls_cache_initial[${key}]}
    done
}

function fill_hardlink_cache {
    if [[ -n "${hls_cache_filled}" ]]; then
        return
    fi
    echo "Filling hardlink cache"
    local line size hardlink
    while read -r line; do
        # <CK>:<HLC>:<size>:<path>
        get_nth_c "${line}" 0 cache_key
        get_nth_c "${line}" 1 hardlink
        update_hls_cache "${hardlink}" "${cache_key}" || :
    done <"${wd}/unchanged_entries"
    mark_hls_cache_as_initial
    hls_cache_filled=x
}

#
# filter entries and compute total size diff
#
# line format of new, deleted, unchanged:
# <size>:<path>
#
# line format of changed:
# <size_diff>:<old_size>:<new_size>:<old_path>@_^_@_^_@<new_path>
#

# new
if any_missing "${wd}/new_entries_total_size_diff" "${wd}/new_entries_filtered"; then
    fill_hardlink_cache
    echo "Filtering new entries"
    restore_hls_cache
    while read -r line; do
        get_nth_c "${line}" 1 new_cache_key
        get_nth_c "${line}" 3 new_hardlink
        update_hls_cache "${new_hardlink}" "${new_cache_key}" || :
    done <"${wd}/changed_entries"

    truncate --size 0 "${wd}/new_entries_filtered"
    total_size_diff=0
    while read -r line; do
        get_nth_c "${line}" 0 cache_key
        get_nth_c "${line}" 1 hardlink
        if ! update_hls_cache "${hardlink}" "${cache_key}"; then
            continue
        fi
        get_nth_c "${line}" 2 size
        strip_n_c "${line}" 3 path
        printf '%s:%s\n' "${size}" "${path}" >>"${wd}/new_entries_filtered"
        total_size_diff=$((total_size_diff + size))
    done <"${wd}/new_entries"
    printf '%d\n' "${total_size_diff}" >"${wd}/new_entries_total_size_diff"
fi

# deleted
if any_missing "${wd}/deleted_entries_total_size_diff" "${wd}/deleted_entries_filtered"; then
    fill_hardlink_cache
    echo "Filtering deleted entries"
    restore_hls_cache
    while read -r line; do
        get_nth_c "${line}" 0 old_cache_key
        get_nth_c "${line}" 2 old_hardlink
        update_hls_cache "${old_hardlink}" "${old_cache_key}" || :
    done <"${wd}/changed_entries"
    truncate --size 0 "${wd}/deleted_entries_filtered"
    total_size_diff=0
    while read -r line; do
        # <CK>:<HLC>:<size>:<path>
        get_nth_c "${line}" 0 cache_key
        get_nth_c "${line}" 1 hardlink
        if ! update_hls_cache "${hardlink}" "${cache_key}"; then
            continue
        fi
        get_nth_c "${line}" 2 size
        strip_n_c "${line}" 3 path
        printf '%s:%s\n' "${size}" "${path}" >>"${wd}/deleted_entries_filtered"
        total_size_diff=$((total_size_diff - size))
    done <"${wd}/deleted_entries"
    printf '%d\n' "${total_size_diff}" >"${wd}/deleted_entries_total_size_diff"
fi

# changed into same, grown and shrunk
if any_missing "${wd}/changed_entries_total_size_diff" "${wd}/changed_entries_filtered_same" \
               "${wd}/changed_entries_filtered_grown" "${wd}/changed_entries_filtered_shrunk"; then
    fill_hardlink_cache
    echo "Filtering changed entries"
    restore_hls_cache
    truncate --size 0 "${wd}/changed_entries_filtered_same"
    truncate --size 0 "${wd}/changed_entries_filtered_grown"
    truncate --size 0 "${wd}/changed_entries_filtered_shrunk"
    total_size_diff=0
    while read -r line; do
        get_nth_c "${line}" 1 new_cache_key
        get_nth_c "${line}" 3 new_hardlink
        if ! update_hls_cache "${new_hardlink}" "${new_cache_key}"; then
            continue
        fi
        get_nth_c "${line}" 4 old_size
        get_nth_c "${line}" 5 new_size
        strip_n_c "${line}" 6 path_pair
        get_nth_p "${path_pair}" 0 old_path
        strip_n_p "${path_pair}" 1 new_path
        size_diff=$((new_size - old_size))
        total_size_diff=$((total_size_diff + size_diff))
        if [[ ${size_diff} -gt 0 ]]; then
            output="${wd}/changed_entries_filtered_grown"
        elif [[ ${size_diff} -lt 0 ]]; then
            output="${wd}/changed_entries_filtered_shrunk"
        else
            output="${wd}/changed_entries_filtered_same"
        fi
        # drop the minus from negative size diff
        size_diff="${size_diff/#-}"
        printf '%s:%s:%s:%s%s%s\n' "${size_diff}" "${old_size}" "${new_size}" "${old_path}" "${PATH_SEP}" "${new_path}" >>"${output}"
    done <"${wd}/changed_entries"
    printf '%d\n' "${total_size_diff}" >"${wd}/changed_entries_total_size_diff"
fi

#
# print reports
#

function xread {
    # shellcheck disable=SC2162 # -r may be passed to read through args
    read "${@}" || :
}

xread -r -d '' awk_simple_prog <<'EOF'
{
    bytes=$1
    path=$2
    kbytes=bytes / 1024
    mbytes=kbytes / 1024
    gbytes=mbytes / 1024
    printf "%s (%d bytes", path, bytes
    if (kbytes >= 1) printf ", %d kbytes", kbytes
    if (mbytes >= 1) printf ", %d mbytes", mbytes
    if (gbytes >= 1) printf ", %d gbytes", gbytes
    printf ")\n"
}
EOF

function simple_report {
    local limit_var_name="${1}"; shift
    local file="${1}"; shift
    local caption="${1}"; shift

    local -n limit_var="${limit_var_name}"
    local lineno

    lineno=$(file_lineno "${file}")
    if [[ "${limit_var}" -gt 0 ]] && [[ "${limit_var}" -lt "${lineno}" ]]; then
        echo "Top ${limit_var} largest ${caption} files (of ${lineno} files total):"
        echo
        # shellcheck disable=SC2154 # awk_simple_prog is assigned through xread
        xsort --reverse --numeric-sort "${file}" | \
            head --lines "${limit_var}" | \
            sed -e 's/:/ /' | \
            xawk "${awk_simple_prog}"
    else
        echo "All ${lineno} ${caption} files:"
        echo
        xsort --reverse --numeric-sort "${file}" | \
            sed -e 's/:/ /' | \
            xawk "${awk_simple_prog}"
    fi
}

echo
simple_report NEW_LIMIT "${wd}/new_entries_filtered" "newly added"
echo
simple_report DELETED_LIMIT "${wd}/deleted_entries_filtered" "just deleted"

function changed_tuple_to_fields {
    local line size_diff old_size new_size path_pair old_path new_path

    while read -r line; do
        get_nth_c "${line}" 0 size_diff
        get_nth_c "${line}" 1 old_size
        get_nth_c "${line}" 2 new_size
        strip_n_c "${line}" 3 path_pair
        get_nth_p "${path_pair}" 0 old_path
        strip_n_p "${path_pair}" 1 new_path
        printf '%s %s %s %s %s\n' "${size_diff}" "${old_size}" "${new_size}" "${old_path}" "${new_path}"
    done
    return 0
}

xread -r -d '' awk_changed_prog <<'EOF'
{
    bytes_diff=$1
    old_bytes=$2
    new_bytes=$3
    old_path=$4
    new_path=$5

    if (old_path != new_path) printf "%s (from %s)", new_path, old_path
    else printf "%s", new_path
    printf " by %d bytes", bytes_diff
    kbytes=bytes_diff / 1024
    mbytes=kbytes / 1024
    gbytes=mbytes / 1024
    if (kbytes >= 1) printf " (%d kbytes", kbytes
    if (mbytes >= 1) printf ", %d mbytes", mbytes
    if (gbytes >= 1) printf ", %d gbytes", gbytes
    if (kbytes >= 1) printf ")"

    printf " from %d bytes", old_bytes
    kbytes=old_bytes / 1024
    mbytes=kbytes / 1024
    gbytes=mbytes / 1024
    if (kbytes >= 1) printf " (%d kbytes", kbytes
    if (mbytes >= 1) printf ", %d mbytes", mbytes
    if (gbytes >= 1) printf ", %d gbytes", gbytes
    if (kbytes >= 1) printf ")"

    printf " to %d bytes", new_bytes
    kbytes=new_bytes / 1024
    mbytes=kbytes / 1024
    gbytes=mbytes / 1024
    if (kbytes >= 1) printf " (%d kbytes", kbytes
    if (mbytes >= 1) printf ", %d mbytes", mbytes
    if (gbytes >= 1) printf ", %d gbytes", gbytes
    if (kbytes >= 1) printf ")"
    printf "\n"
}
EOF

function changed_report {
    local limit_var_name="${1}"; shift
    local file="${1}"; shift
    local caption="${1}"; shift

    local -n limit_var="${limit_var_name}"
    local lineno

    lineno=$(file_lineno "${file}")
    if [[ "${limit_var}" -gt 0 ]] && [[ "${limit_var}" -lt "${lineno}" ]]; then
        echo "Top ${limit_var} ${caption} in size files (of ${lineno} files total):"
        echo
        # shellcheck disable=SC2154 # awk_changed_prog is assigned through xread
        xsort --reverse --numeric-sort "${file}" | \
            head --lines "${limit_var}" | \
            changed_tuple_to_fields | \
            xawk "${awk_changed_prog}"
    else
        echo "All ${lineno} ${caption} files:"
        echo
        xsort --reverse --numeric-sort "${file}" | \
            changed_tuple_to_fields | \
            xawk "${awk_changed_prog}"
    fi
}

echo
changed_report GROWN_LIMIT "${wd}/changed_entries_filtered_grown" "grown"
echo
changed_report SHRUNK_LIMIT "${wd}/changed_entries_filtered_shrunk" "shrunk"

xread -r -d '' awk_total_size_prog <<'EOF'
{
    bytes=$1
    sign="increased"
    if (bytes < 0) { sign="decreased"; bytes = -bytes; }
    kbytes=bytes / 1024
    mbytes=kbytes / 1024
    gbytes=mbytes / 1024
    printf "Total size difference: %s by %d bytes", sign, bytes
    if (kbytes >= 1) printf " (%d kbytes", kbytes
    if (mbytes >= 1) printf ", %d mbytes", mbytes
    if (gbytes >= 1) printf ", %d gbytes", gbytes
    if (kbytes >= 1) printf ")"
    printf "\n"
}
EOF

echo
size_diff_files=(
    "${wd}/new_entries_total_size_diff"
    "${wd}/deleted_entries_total_size_diff"
    "${wd}/changed_entries_total_size_diff"
)
# shellcheck disable=SC2154 # awk_total_size_prog is assigned through xread
xawk "${awk_total_size_prog}" <<<$(($(cat "${size_diff_files[@]}" | paste -sd+ -)))
