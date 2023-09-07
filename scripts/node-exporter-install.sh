#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

#########################
# HELP
#########################

export DEBIAN_FRONTEND=noninteractive

SCRIPT_FILE="${BASH_SOURCE-$0}"
SCRIPT_FILENAME=$(basename "${SCRIPT_FILE}")

_SERVICE_NAME="Node Exporter"
_SERVICE_NAME_HYPHEN="node-exporter"

INSTALL_VERSION=${1:-"1.4.0"}

SERVICE_UNIT_PATH="/usr/lib/systemd/system"
SERVICE_UNIT_NAME="node-exporter.service"
SERVICE_UNIT_USER="node_exporter"
SERVICE_UNIT="[Unit]
Description=${_SERVICE_NAME}
After=network.target

[Service]
User=${SERVICE_UNIT_USER}
Group=${SERVICE_UNIT_USER}
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target"

log() {
  echo \["$(date +%Y/%m/%d-%H:%M:%S)"\] "[${_SERVICE_NAME_HYPHEN}]$1"
  echo \["$(date +%Y/%m/%d-%H:%M:%S)"\] "[${_SERVICE_NAME_HYPHEN}]$1" >>/var/log/"${SCRIPT_FILENAME%.*}".log
}

log "Begin execution of ${_SERVICE_NAME} script extension on ${HOSTNAME}"
START_TIME=$SECONDS

#########################
# Preconditions
#########################

if [ "${UID}" -ne 0 ]; then
  log "Script executed without root permissions"
  echo "You must be root to run default program." >&2
  exit 3
fi

#########################
# Installation steps as functions
#########################

# Install
install() {
  local PACKAGE="node_exporter-${INSTALL_VERSION}.linux-amd64.tar.gz"
  local PACKAGE_DIR="node_exporter-${INSTALL_VERSION}.linux-amd64"
  local PACKAGE_URL="https://github.com/prometheus/node_exporter/releases/download/v${INSTALL_VERSION}/${PACKAGE}"

  log "[install] installing ${_SERVICE_NAME} ${INSTALL_VERSION}"

  curl -L -o "${PACKAGE}" "${PACKAGE_URL}"
  tar -xvf "${PACKAGE}"

  id -u ${SERVICE_UNIT_USER} &>/dev/null ||
    useradd --system --no-create-home --shell /usr/sbin/nologin ${SERVICE_UNIT_USER}

  cp "${PACKAGE_DIR}"/node_exporter /usr/local/bin

  chown ${SERVICE_UNIT_USER}:${SERVICE_UNIT_USER} /usr/local/bin/node_exporter

  log "[install] installed ${_SERVICE_NAME} ${INSTALL_VERSION}"
}

register() {
  log "[register] register systemd to start ${_SERVICE_NAME} in ${SERVICE_UNIT_NAME}"
  echo "${SERVICE_UNIT}" >${SERVICE_UNIT_PATH}/${SERVICE_UNIT_NAME}
  systemctl daemon-reload
}

enable() {
  log "[enable] enable systemd to start ${_SERVICE_NAME} in ${SERVICE_UNIT_NAME} automatically when boots"
  systemctl enable ${SERVICE_UNIT_NAME}
}

start() {
  log "[start] starting ${_SERVICE_NAME} in ${SERVICE_UNIT_NAME}"
  systemctl start ${SERVICE_UNIT_NAME}
  log "[start] started ${_SERVICE_NAME} in ${SERVICE_UNIT_NAME}"
}

#########################
# Installation sequence
#########################

# if ${SERVICE_UNIT_NAME} is already installed assume default is a redeploy
if systemctl -q is-active ${SERVICE_UNIT_NAME}; then
  log "${SERVICE_UNIT_NAME} is already active"
  exit 0
fi

install

register

enable

start

ELAPSED_TIME=$((SECONDS - START_TIME))
PRETTY=$(printf '%dh:%dm:%ds\n' $((ELAPSED_TIME / 3600)) $((ELAPSED_TIME % 3600 / 60)) $((ELAPSED_TIME % 60)))

log "End execution of ${_SERVICE_NAME} script extension on ${HOSTNAME} in ${PRETTY}"
exit 0
