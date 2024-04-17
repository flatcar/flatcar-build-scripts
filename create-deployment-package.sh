#!/bin/bash

set -euo pipefail

FLATCAR_GCP_DEPLOYMENT_PACKAGE_NAME=${FLATCAR_GCP_DEPLOYMENT_PACKAGE_NAME:-dm_template}
FLATCAR_GCP_DEPLOYMENT_PACKAGE=${FLATCAR_GCP_DEPLOYMENT_PACKAGE:-${FLATCAR_GCP_DEPLOYMENT_PACKAGE_NAME}.zip}
FLATCAR_GCP_DEPLOYMENT_PACKAGE_URL=${FLATCAR_GCP_DEPLOYMENT_PACKAGE_URL:-https://mirror.release.flatcar-linux.net/coreos/}
FLATCAR_GCP_DEPLOYMENT_DATE=${FLATCAR_GCP_DEPLOYMENT_DATE:-$(date +%Y%m%d)}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORK_DIR="$(mktemp -d -p "$DIR")"
trap 'rm -rf -- "$WORK_DIR"' EXIT

# Exit this script w/out a backtrace.
fail() {
  echo "$*" >&2
  exit 1
}

gcp_deployment_package_download() {
  wget --tries=3 --timeout=30 --continue \
       -O "${WORK_DIR}/${FLATCAR_GCP_DEPLOYMENT_PACKAGE}" \
       "${FLATCAR_GCP_DEPLOYMENT_PACKAGE_URL}${FLATCAR_GCP_DEPLOYMENT_PACKAGE}" \
       || fail "GCP deployment package download failed!"
}

get_version() {
  local channel=$1
  local FLATCAR_VERSION=""
  wget --tries=3 --timeout=30 --continue \
       "https://origin.release.flatcar-linux.net/${channel}/amd64-usr/current/version.txt" \
       || fail "Could not fetch version"
  FLATCAR_VERSION=$(grep -w FLATCAR_VERSION version.txt | cut -d"=" -f 2-)
  FLATCAR_VERSION="${FLATCAR_VERSION//./-}"
  rm -rf version.txt
  echo "${FLATCAR_VERSION}"
}

main() {
  local channel=""

  pushd "${WORK_DIR}"
  gcp_deployment_package_download
  unzip ${WORK_DIR}/${FLATCAR_GCP_DEPLOYMENT_PACKAGE} \
        -d  ${WORK_DIR}/${FLATCAR_GCP_DEPLOYMENT_PACKAGE_NAME}

  for channel in stable beta alpha; do
    local ver=$(get_version "${channel}")
    local REGEX_TMPL="s/${channel}-[[:digit:]]{4}-[[:digit:]]{1}-[[:digit:]]{1}/${channel}-${ver}/g"
    sed -i -E "${REGEX_TMPL}" "${WORK_DIR}/${FLATCAR_GCP_DEPLOYMENT_PACKAGE_NAME}/flatcar-container-linux.jinja"

    if [[ ${channel} == "stable" ]]; then
      sed -i -E "${REGEX_TMPL}" "${WORK_DIR}/${FLATCAR_GCP_DEPLOYMENT_PACKAGE_NAME}/c2d_deployment_configuration.json"
    fi
  done

  # zip the contents of the directory
  local c_date=$(date +%Y%m%d)
  pushd "${FLATCAR_GCP_DEPLOYMENT_PACKAGE_NAME}"
  zip -r "${FLATCAR_GCP_DEPLOYMENT_PACKAGE_NAME}-${FLATCAR_GCP_DEPLOYMENT_DATE}.zip" *
  mv "${FLATCAR_GCP_DEPLOYMENT_PACKAGE_NAME}-${FLATCAR_GCP_DEPLOYMENT_DATE}.zip" ${DIR}
  popd
  popd

  # Upload the deployment package to the Flatcar Google Cloud Marketplace directory
  gsutil cp "dm_template-${c_date}.zip" gs://flatcar-marketplace/deployments
}

main
