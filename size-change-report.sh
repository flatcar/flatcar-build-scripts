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
### spec is a string in one of two forms:
### release:<channel>:<board>:<version> (e.g. release:alpha:amd64-usr:3480.0.0)
### bincache:<arch>:<version> (e.g. bincache:amd64:3483.0.0+weekly-updates-11)
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
            NEW_LIMIT="${2}";
            shift
            ;;
        -d) DELETED_LIMIT="${2}";
            shift
            ;;
        -g) GROWN_LIMIT="${2}";
            shift
            ;;
        -s) SHRUNK_LIMIT="${2}";
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

# spec can be:
#
# release:CHANNEL:BOARD:VERSION
# bincache:ARCH:VERSION
function handle_spec {
    local spec="${1}"; shift
    local output="${1}"; shift

    if [[ $(wc -l <<<"${spec}") -ne 1 ]]; then
        fail "Invalid spec '${spec}', can't be multiline"
    fi

    local -a spec_a url

    mapfile -t spec_a < <(tr ':' '\n' <<<"${spec}")

    case "${spec_a}" in
        release)
            if [[ "${#spec_a[@]}" -ne 4 ]]; then
                fail "Invalid release spec '${spec}', should be in form of release:CHANNEL:BOARD:VERSION"
            fi
            local from channel board version
            from='release'
            channel="${spec_a[1]}"
            board="${spec_a[2]}"
            version="${spec_a[3]}"
            url="https://${channel}.release.flatcar-linux.net/${board}/${version}"
            ;;
        bincache)
            if [[ "${#spec_a[@]}" -ne 3 ]]; then
                fail "Invalid bincache spec '${spec}', should be in form of bincache:ARCH:VERSION"
            fi
            local from arch version
            from="bincache"
            arch="${spec_a[1]}"
            version="${spec_a[2]}"
            url="https://bincache.flatcar-linux.net/images/${arch}/${version}"
            ;;
        *)
            fail "Invalid spec '${spec}', should have either release or bincache for first kind"
            ;;
    esac
    curl --location --silent -S -o "${output}" "${url}/flatcar_production_image_contents.txt"
}

: ${WORKDIR:=}
: ${KEEP_WORKDIR:=}

if [[ -z "${WORKDIR}" ]]; then
    WORKDIR=$(mktemp --tmpdir --directory "scr-XXXXXXXX")
    # print workdir only if we are going to keep it
    if [[ -n ${KEEP_WORKDIR} ]]; then
        echo "Workdir in ${WORKDIR}"
    fi
fi

mkdir -p "${WORKDIR}"

if [[ -z ${KEEP_WORKDIR} ]]; then
    trap "rm -rf '${WORKDIR}'" EXIT
fi

wd="${WORKDIR}"

if [[ ! -e "${wd}/A" ]] || [[ ! -e "${wd}/B" ]]; then
    echo "Downloading file listings"
    handle_spec "${spec_a}" "${wd}/A"
    handle_spec "${spec_b}" "${wd}/B"
fi

function xgrep {
    grep "${@}" || :
}

function xawk {
    awk "${@}" || :
}

function xgit-diff {
    git diff "${@}" || :
}

function xsort {
    sort "${@}" || :
}

function file_lineno {
    wc -l "${1}" | cut -d' ' -f1
}

if [[ ! -e "${wd}/output" ]] || [[ ! -e "${wd}/detailed_output" ]]; then
    echo "Generating file listing diffs"
    for f in "${wd}/A" "${wd}/B"; do
        # Cut date and time noise away
        sed -e 's/....-..-.. ..:.. //g' "${f}" >"${f}.1.no-date-time"
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
    done

    # drop all the diff noise
    xgit-diff \
        --no-index \
        -- \
        "${wd}/A.6a.no-slsa" "${wd}/B.6a.no-slsa" | \
        tail --lines +6 | \
        xgrep -v '^@' >"${wd}/output"

    # use a ginormous amount of context to capture all the unmodified
    # files, will be needed for hardlink hunting
    lineno_a=$(file_lineno "${wd}/A.4b.cut-kernel")
    lineno_b=$(file_lineno "${wd}/B.4b.cut-kernel")
    lineno=${lineno_a}
    if [[ ${lineno} -lt ${lineno_b} ]]; then
        lineno=${lineno_b}
    fi
    # also skip first 5 lines of diff noise
    xgit-diff \
        --unified=${lineno} \
        --no-index \
        -- \
        "${wd}/A.4b.cut-kernel" "${wd}/B.4b.cut-kernel" | \
        tail --lines +6 >"${wd}/detailed_output"
fi

#
# categorize stuff into new, deleted, changed and unchanged
#
# line format of new, deleted, unchanged:
# <size>:<hardlink>:<path>
#
# line format of changed:
# <old_size>:<old_hardlink>:<new_size>:<new_hardlink>:<old_path>@_^_@_^_@<new_path>
#

PATH_SEP='@_^_@_^_@'

# new
if [[ ! -e "${wd}/new_entries" ]]; then
    echo "Generating new entries"
    new_entries=()
    mapfile -t new_entries < <(xgrep -e '^+/' "${wd}/output" | sed -e 's/^+//')

    truncate --size 0 "${wd}/new_entries"
    for new_entry in "${new_entries[@]}"; do
        regexp='^\+.* \.'
        regexp+="${new_entry//0/[0-9]+(\.[0-9]+)*}"
        regexp+='$'
        fields=()
        while read -r -a fields; do
            hardlink="${fields[1]}"
            size="${fields[4]}"
            path="${fields[5]}"
            printf '%s:%s:%s\n' "${size}" "${hardlink}" "${path}" >>"${wd}/new_entries"
        done < <(xgrep -E -e "${regexp}" "${wd}/detailed_output")
    done
    unset new_entries fields
fi

# deleted
if [[ ! -e "${wd}/deleted_entries" ]]; then
    echo "Generating deleted entries"
    deleted_entries=()
    mapfile -t deleted_entries < <(xgrep -e '^-/' "${wd}/output" | sed -e 's/^-//')

    truncate --size 0 "${wd}/deleted_entries"
    for deleted_entry in "${deleted_entries[@]}"; do
        regexp='^\-.* \.'
        regexp+="${deleted_entry//0/[0-9]+(\.[0-9]+)*}"
        regexp+='$'
        fields=()
        while read -r -a fields; do
            hardlink="${fields[1]}"
            size="${fields[4]}"
            path="${fields[5]}"
            printf '%s:%s:%s\n' "${size}" "${hardlink}" "${path}" >>"${wd}/deleted_entries"
        done < <(xgrep -E -e "${regexp}" "${wd}/detailed_output")
    done
    unset deleted_entries fields
fi

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
    local regexp_pre_so regexp_post_so

    # handle so versions specially, pre .so. part will receive a different number matching than the po .so. part
    if [[ "${regexp}" = *'\.so\.'* ]]; then
        regexp_pre_so="${regexp%%\\.so\\.*}"
        # turn all dot separated numbers into a regexp matching dot separated numbers
        regexp_pre_so="$(sed -E 's/[0-9]+(\.[0-9]+)*/[0-9]\\+\\(\\.[0-9]\\+\\)*/g' <<<"${regexp_pre_so}")"
        regexp_post_so="${regexp#*\\.so\\.}"
        # turn every number into a regexp matching any number
        regexp_post_so="$(sed -E 's/[0-9]+/[0-9]\\+/g' <<<"${regexp_post_so}")"
        regexp="${regexp_pre_so}"'\.so\.'"${regexp_post_so}"
    else
        # turn all dot separated numbers into a regexp matching dot separated numbers
        regexp="$(sed -E 's/[0-9]+(\.[0-9]+)*/[0-9]\\+\\(\\.[0-9]\\+\\)*/g' <<<"${regexp}")"
    fi

    printf '%s\n' "${regexp}"
}

# changed
if [[ ! -e "${wd}/changed_entries" ]]; then
    echo "Generating changed entries"
    xgrep '^+' "${wd}/detailed_output" >"${wd}/diff-plus-only"
    xgrep '^-' "${wd}/detailed_output" >"${wd}/diff-minus-only"

    truncate --size 0 "${wd}/changed_entries"
    fields=()
    while read -r -a fields; do
        old_hardlink="${fields[1]}"
        old_size="${fields[4]}"
        old_path="${fields[5]}"
        regexp=$(munge_path_into_regexp "${old_path}")
        regexp=$(munge_numbers_into_regexps "${regexp}")
        regexp='^\+.*[^>] '"${regexp}"'$'
        results=()
        mapfile -t results < <(xgrep -e "${regexp}" "${wd}/diff-plus-only")
        if [[ ${#results[@]} -eq 0 ]]; then
            continue
        elif [[ ${#results[@]} -gt 1 ]]; then
            found=
            # 1. try the same path
            regexp2=$(munge_path_into_regexp "${old_path}")
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
                regexp2_base_part=$(munge_numbers_into_regexps "${regexp2_base_part}")
                regexp2="${regexp2_dir_part}/${regexp2_base_part}"
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
                results2=()
                mapfile -t results2 < <(printf '%s\n' "${results[@]}" | xgrep -e "${regexp2}")
                if [[ ${#results2[@]} -gt 0 ]]; then
                    results=( "${results2[0]}" )
                    found=x
                fi
            fi
        fi
        read -r -a fields <<<"${results[0]}"
        new_hardlink="${fields[1]}"
        new_size="${fields[4]}"
        new_path="${fields[5]}"
        printf '%s:%s:%s:%s:%s%s%s\n' "${old_size}" "${old_hardlink}" "${new_size}" "${new_hardlink}" "${old_path}" "${PATH_SEP}" "${new_path}" >>"${wd}/changed_entries"
    done <"${wd}/diff-minus-only"
    unset results results2 fields
fi

# unchanged
if [[ ! -e "${wd}/unchanged_entries" ]]; then
    echo "Generating unchanged entries"
    fields=()
    truncate --size 0 "${wd}/unchanged_entries"
    while read -r -a fields; do
        hardlink="${fields[1]}"
        size="${fields[4]}"
        path="${fields[5]}"
        printf '%s:%s:%s\n' "${size}" "${hardlink}" "${path}" >>"${wd}/unchanged_entries"
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
        stripped="${stripped#*${sep}}"
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
    out_var="${gn_tmp_v%%${sep}*}"
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

# used for ignoring repeating hardlinks of the same size and hardlink count
declare -A hls_cache
hls_cache=()
declare -A hls_cache_initial
hls_cache_initial=()
hls_cache_filled=

function update_hls_cache {
    local hardlink="${1}"; shift
    local size="${1}"; shift

    if [[ ${hardlink} -eq 1 ]]; then
        return 0
    fi
    local key="${hardlink}:${size}"
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
        get_nth_c "${line}" 0 size
        get_nth_c "${line}" 1 hardlink
        update_hls_cache "${hardlink}" "${size}" || :
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
if [[ ! -e "${wd}/new_entries_total_size_diff" ]] || [[ ! -e "${wd}/new_entries_filtered" ]]; then
    fill_hardlink_cache
    echo "Filtering new entries"
    restore_hls_cache
    while read -r line; do
        get_nth_c "${line}" 2 new_size
        get_nth_c "${line}" 3 new_hardlink
        update_hls_cache "${new_hardlink}" "${new_size}" || :
    done <"${wd}/changed_entries"

    truncate --size 0 "${wd}/new_entries_filtered"
    total_size_diff=0
    while read -r line; do
        get_nth_c "${line}" 0 size
        get_nth_c "${line}" 1 hardlink
        if ! update_hls_cache "${hardlink}" "${size}"; then
            continue
        fi
        strip_n_c "${line}" 2 path
        printf '%s:%s\n' "${size}" "${path}" >>"${wd}/new_entries_filtered"
        total_size_diff=$((total_size_diff + size))
    done <"${wd}/new_entries"
    printf '%d\n' "${total_size_diff}" >"${wd}/new_entries_total_size_diff"
fi

# deleted
if [[ ! -e "${wd}/deleted_entries_total_size_diff" ]] || [[ ! -e "${wd}/deleted_entries_filtered" ]]; then
    fill_hardlink_cache
    echo "Filtering deleted entries"
    restore_hls_cache
    while read -r line; do
        get_nth_c "${line}" 0 old_size
        get_nth_c "${line}" 1 old_hardlink
        update_hls_cache "${old_hardlink}" "${old_size}" || :
    done <"${wd}/changed_entries"
    truncate --size 0 "${wd}/deleted_entries_filtered"
    total_size_diff=0
    while read -r line; do
        get_nth_c "${line}" 0 size
        get_nth_c "${line}" 1 hardlink
        if ! update_hls_cache "${hardlink}" "${size}"; then
            continue
        fi
        strip_n_c "${line}" 2 path
        printf '%s:%s\n' "${size}" "${path}" >>"${wd}/deleted_entries_filtered"
        total_size_diff=$((total_size_diff - size))
    done <"${wd}/deleted_entries"
    printf '%d\n' "${total_size_diff}" >"${wd}/deleted_entries_total_size_diff"
fi

# changed into same, grown and shrunk
#
if [[ ! -e "${wd}/changed_entries_total_size_diff" ]] || \
       [[ ! -e "${wd}/changed_entries_filtered_same" ]] || \
       [[ ! -e "${wd}/changed_entries_filtered_grown" ]] || \
       [[ ! -e "${wd}/changed_entries_filtered_shrunk" ]]; then
    fill_hardlink_cache
    echo "Filtering changed entries"
    restore_hls_cache
    truncate --size 0 "${wd}/changed_entries_filtered_same"
    truncate --size 0 "${wd}/changed_entries_filtered_grown"
    truncate --size 0 "${wd}/changed_entries_filtered_shrunk"
    total_size_diff=0
    while read -r line; do
        get_nth_c "${line}" 2 new_size
        get_nth_c "${line}" 3 new_hardlink
        if ! update_hls_cache "${new_hardlink}" "${new_size}"; then
            continue
        fi
        get_nth_c "${line}" 0 old_size
        strip_n_c "${line}" 4 path_pair
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

    if (old_path != new path) printf "%s (from %s)", new_path, old_path
    else printf "%s" new_path
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
    if (kbytes >= 1) printf ")\n"
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
xawk "${awk_total_size_prog}" <<<$(($(cat "${size_diff_files[@]}" | paste -sd+ -)))
