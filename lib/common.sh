#!/bin/bash
#
# common.sh includes common variables and functions to be shared by
# scripts under the flatcar-build-scripts repo.

export FLATCAR_REPOS=(
  "afterburn"
  "baselayout"
  "bootengine"
  "chromite"
  "coreos-cloudinit"
  "coreos-overlay"
  "dev-util"
  "docker"
  "efunctions"
  "etcd"
  "etcdctl"
  "fero"
  "grub"
  "ignition"
  "init"
  "locksmith"
  "mantle"
  "mayday"
  "nss-altfiles"
  "portage-stable"
  "rkt"
  "scripts"
  "sdnotify-proxy"
  "seismograph"
  "shim"
  "sysroot-wrappers"
  "toolbox"
  "torcx"
  "update-ssh-keys"
  "update_engine"
  "updateservicectl"
)
