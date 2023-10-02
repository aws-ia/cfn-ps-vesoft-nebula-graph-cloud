#!/bin/bash

LICENSE_LINK=$1
LICENSE_COMPONENT=${2:-"all"}

log() {
  echo \["$(date +%Y/%m/%d-%H:%M:%S)"\] "$1"
  echo \["$(date +%Y/%m/%d-%H:%M:%S)"\] "$1" >>/var/log/nebula-license-install.log
}

if [ -z "${LICENSE_LINK}" ]; then
  log "[install_license] license link is empty!"
  exit 0
fi

# Install
install_license() {
  log "[install_license] download NebulaGraph license"
  wget -O nebulagraph-license.tar.gz "${LICENSE_LINK}"

  local EXIT_CODE=$?
  if [ $EXIT_CODE -ne 0 ]; then
    log "[install_license] download NebulaGraph license failed"
    exit $EXIT_CODE
  fi
}

uncompress_license() {
  log "[replace_license] uncompress license package"
  tar -xzf nebulagraph-license.tar.gz
  case $LICENSE_COMPONENT in
    "nebula")
      cp nebulagraph-license/nebula.license .
      ;;
    "tools")
      cp nebulagraph-license/nebula-*.license .
      ;;
    "all")
      cp nebulagraph-license/* .
      ;;
  esac
  rm -rf nebulagraph-license
  rm nebulagraph-license.tar.gz
}

install_license
uncompress_license

exit 0
