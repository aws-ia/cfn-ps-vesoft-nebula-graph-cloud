#!/bin/bash

#########################
# HELP
#########################

export DEBIAN_FRONTEND=noninteractive

log() {
  echo \["$(date +%Y/%m/%d-%H:%M:%S)"\] "$1"
  echo \["$(date +%Y/%m/%d-%H:%M:%S)"\] "$1" >>/var/log/nebula-analytics-install.log
}

log "Begin execution of NebulaGraph Analytics script extension on ${HOSTNAME}"

#########################
# Preconditions
#########################

ANALYTICS_VERSION=${1:-"3.2.1"}

#########################
# Installation steps as functions
#########################
install_analytics() {
  local OS_SUFFIX="x86_64"
  local OS_VERSION="ubuntu"
  local PACKAGE="nebula-analytics-${ANALYTICS_VERSION}-${OS_VERSION}.${OS_SUFFIX}.tar.gz"

  log "[install_analytics] nebula analytics version ${ANALYTICS_VERSION} "

  chmod +x nebula-download
  ./nebula-download analytics --version="${ANALYTICS_VERSION}"

  local EXIT_CODE=$?
  if [ ${EXIT_CODE} -ne 0 ]; then
    log "[install_analytics] error downloading Nebula Analytics ${ANALYTICS_VERSION}"
    exit ${EXIT_CODE}
  fi

  apt update -y
  apt install libgomp1 -y
  tar -zxvf "${PACKAGE}" -C /usr/local
  log "[install_analytics] installed Nebula Analytics ${ANALYTICS_VERSION}"
}

install_analytics

log "End execution of NebulaGraph Analytics script extension on ${HOSTNAME}"
exit 0
