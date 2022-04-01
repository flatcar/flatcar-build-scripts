#!/bin/bash

set -euo pipefail

shopt -s extglob

this_dir="$(dirname "${0}")"

: ${PORTAGE_STABLE:="${this_dir}/portage-stable/main//"}

ebuild_files=($(find "${PORTAGE_STABLE}" -name '*.ebuild'))
eclass_files=($(find "${PORTAGE_STABLE}" -name '*.eclass'))

declare -A pkgs
declare -A eclasses

for eclass in "${eclass_files[@]}"; do
    # strip portage-stable prefix
    eclassname="${eclass#${PORTAGE_STABLE}}"
    # strip all leading slashes
    eclassname="${eclassname##*(/)}"
    if [[ "${eclassname}" = 'eclass/usr-ldscript.eclass' ]]; then
        date_to_check=0
    else
        cpl="$(head --lines 1 "${eclass}" | grep -o 'Copyright\s\+[0-9]\+\(-[0-9]\+\)\?')"
        # strip Copyright and following whitespace
        dates="${cpl##Copyright*([ \t])}"
        if [[ "${dates}" =~ - ]]; then
            # take the second date in case of date range
            date_to_check="${dates#*-}"
        else
            date_to_check="${dates}"
        fi
    fi
    if [[ -z "${eclasses[${eclassname}]+ISSET}" ]]; then
        eclasses["${eclassname}"]=0
    fi
    if [[ ${date_to_check} -gt eclasses["${eclassname}"] ]]; then
        eclasses["${eclassname}"]="${date_to_check}"
    fi
done

for ebuild in "${ebuild_files[@]}"; do
    # dirname
    pkgname="${ebuild%/*}"
    # strip portage-stable prefix
    pkgname="${pkgname#${PORTAGE_STABLE}}"
    # strip all leading slashes
    pkgname="${pkgname##*(/)}"
    cpl="$(head --lines 1 "${ebuild}" | grep -o 'Copyright\s\+[0-9]\+\(-[0-9]\+\)\?')"
    # strip Copyright and following whitespace
    dates="${cpl##Copyright*([ \t])}"
    if [[ "${dates}" =~ - ]]; then
        # take the second date in case of date range
        date_to_check="${dates#*-}"
    else
        date_to_check="${dates}"
    fi
    if [[ -z "${pkgs[${pkgname}]+ISSET}" ]]; then
        pkgs["${pkgname}"]=0
    fi
    if [[ ${date_to_check} -gt pkgs["${pkgname}"] ]]; then
        pkgs["${pkgname}"]="${date_to_check}"
    fi
done

declare -A pkgs_by_date
declare -A eclasses_by_date
declare -A all_dates

for pkg in "${!pkgs[@]}"; do
    date="${pkgs[${pkg}]}"
    all_dates["${date}"]=1
    if [[ -z "${pkgs_by_date[${date}]+ISSET}" ]]; then
        pkgs_by_date["${date}"]="${pkg}"
    else
        pkgs_by_date["${date}"]+=";${pkg}"
    fi
done

for eclass in "${!eclasses[@]}"; do
    date="${eclasses[${eclass}]}"
    all_dates["${date}"]=1
    if [[ -z "${eclasses_by_date[${date}]+ISSET}" ]]; then
        eclasses_by_date["${date}"]="${eclass}"
    else
        eclasses_by_date["${date}"]+=";${eclass}"
    fi
done

all_dates_sorted=($(printf '%s\n' "${!all_dates[@]}" | sort))

for date in "${all_dates_sorted[@]}"; do
    echo "!!!!"
    echo "${date}"
    echo "!!!!"
    echo ''
    if [[ -n "${pkgs_by_date[${date}]+ISSET}" ]]; then
        set -o noglob
        sorted_ebuilds=( $(printf '%s' "${pkgs_by_date[${date}]}" | tr ';' '\n' | sort -u | tr '\n' ' ') )
        set +o noglob
        echo 'ebuilds:'
        echo '========'
        echo
        last_category=''
        pkgs_in_category=()
        for ebuild in "${sorted_ebuilds[@]}"; do
            category="${ebuild%/*}"
            if [[ "${category}" != "${last_category}" ]]; then
                if [[ ${#pkgs_in_category[@]} -gt 0 ]]; then
                    echo "    ${pkgs_in_category[*]}"
                    echo
                fi
                last_category="${category}"
                echo "${category}:"
                echo
                pkgs_in_category=( "${ebuild}" )
            else
                pkgs_in_category+=( "${ebuild}" )
            fi
        done
        if [[ ${#pkgs_in_category[@]} -gt 0 ]]; then
            echo "    ${pkgs_in_category[*]}"
            echo
        fi
    fi
    if [[ -n "${eclasses_by_date[${date}]+ISSET}" ]]; then
        sorted_eclasses=$(printf '%s' "${eclasses_by_date[${date}]}" | tr ';' '\n' | sort -u | tr '\n' ' ')
        echo 'eclasses:'
        echo '========='
        echo
        echo "${sorted_eclasses}"
        echo
    fi
done
