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

_SERVICE_NAME="Prometheus"
_SERVICE_NAME_HYPHEN="prometheus"

INSTALL_VERSION="2.39.1"
DEPLOYMENT_ID=""
AWS_REGION=""
AWS_IAM_ROLE_ARN=""

SERVICE_UNIT_PATH="/usr/lib/systemd/system"
SERVICE_UNIT_NAME="prometheus.service"
SERVICE_UNIT_USER="prometheus"
SERVICE_UNIT="[Unit]
Description=${_SERVICE_NAME}
After=network.target

[Service]
User=${SERVICE_UNIT_USER}
Group=${SERVICE_UNIT_USER}
Type=simple
ExecStart=/usr/local/bin/prometheus \
          --config.file /etc/prometheus/prometheus.yml \
          --web.listen-address '0.0.0.0:19090' \
          --enable-feature agent \
          --storage.agent.path /var/lib/prometheus/data-agent \
          --web.console.templates /etc/prometheus/consoles \
          --web.console.libraries /etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target"

help() {
  echo "This script installs ${_SERVICE_NAME} on Ubuntu"
  echo ""
  echo "Options:"
  echo "    -v      ${_SERVICE_NAME} version, default: 2.39.1"
  echo "    -d      the deployment id"
  echo "    -r      the aws region"
  echo "    -C      the aws iam role arn"
  echo "    -h      view default help content"
}

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
# Parameter handling
#########################

#Loop through options passed
while getopts :v:d:r:C:h optname; do
  log "Option ${optname} set"
  case $optname in
    v) # set install version
      INSTALL_VERSION="${OPTARG}"
      ;;
    d) # set deployment id
      DEPLOYMENT_ID="${OPTARG}"
      ;;
    r) # set aws region
      AWS_REGION="${OPTARG}"
      ;;
    C) # set aws iam role arn
      AWS_IAM_ROLE_ARN="${OPTARG}"
      ;;
    h) #show help
      help
      exit 2
      ;;
    \?) #unrecognized option - show help
      echo -e \\n"Option -${BOLD}$OPTARG${NORM} not allowed."
      help
      exit 2
      ;;
  esac
done

#########################
# Installation steps as functions
#########################

# Install
install() {
  local PACKAGE="prometheus-${INSTALL_VERSION}.linux-amd64.tar.gz"
  local PACKAGE_DIR="prometheus-${INSTALL_VERSION}.linux-amd64"
  local PACKAGE_URL="https://github.com/prometheus/prometheus/releases/download/v${INSTALL_VERSION}/${PACKAGE}"

  log "[install] installing ${_SERVICE_NAME} ${INSTALL_VERSION}"

  curl -L -o "${PACKAGE}" "${PACKAGE_URL}"
  tar -xvf "${PACKAGE}"

  id -u ${SERVICE_UNIT_USER} &>/dev/null ||
    useradd --system --no-create-home --shell /usr/sbin/nologin ${SERVICE_UNIT_USER}

  mkdir -p /etc/prometheus
  mkdir -p /var/lib/prometheus
  cp "${PACKAGE_DIR}"/prometheus /usr/local/bin
  cp "${PACKAGE_DIR}"/promtool /usr/local/bin/
  cp -r "${PACKAGE_DIR}"/prometheus.yml /etc/prometheus
  cp -r "${PACKAGE_DIR}"/consoles /etc/prometheus
  cp -r "${PACKAGE_DIR}"/console_libraries /etc/prometheus

  chown ${SERVICE_UNIT_USER}:${SERVICE_UNIT_USER} /usr/local/bin/prometheus
  chown ${SERVICE_UNIT_USER}:${SERVICE_UNIT_USER} /usr/local/bin/promtool
  chown -R ${SERVICE_UNIT_USER}:${SERVICE_UNIT_USER} /etc/prometheus
  chown -R ${SERVICE_UNIT_USER}:${SERVICE_UNIT_USER} /var/lib/prometheus

  log "[install] installed ${_SERVICE_NAME} ${INSTALL_VERSION}"
}

configure() {
  local PROMETHEUS_CONF_FILE="/etc/prometheus/prometheus.yml"
  local PROMETHEUS_CONF="
global:
  scrape_interval:     10s
  evaluation_interval: 10s
  external_labels:
    nebulagraph_deployment_id: ${DEPLOYMENT_ID}

#remote_write:
#  - url: http://ENDPOINT_ADDRESS:10908/api/v1/receive
#    headers:
#      THANOS-TENANT: DEPLOYMENT_ID

scrape_configs:
  - job_name: 'node-exporter'
    ec2_sd_configs:
      - region: ${AWS_REGION}
        profile: ${AWS_IAM_ROLE_ARN}
        port: 9100
        filters:
          - name: tag:nebulagraph:cloud:deployment:id
            values:
              - ${DEPLOYMENT_ID}
  - job_name: 'nebula-stats-exporter'
    static_configs:
      - targets: ['127.0.0.1:9200']
"

  log "[configure] configure ${PROMETHEUS_CONF_FILE} for ${_SERVICE_NAME}"
  echo "${PROMETHEUS_CONF}" >${PROMETHEUS_CONF_FILE}
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

configure

register

# do not start it
# enable
# start

ELAPSED_TIME=$((SECONDS - START_TIME))
PRETTY=$(printf '%dh:%dm:%ds\n' $((ELAPSED_TIME / 3600)) $((ELAPSED_TIME % 3600 / 60)) $((ELAPSED_TIME % 60)))

log "End execution of ${_SERVICE_NAME} script extension on ${HOSTNAME} in ${PRETTY}"
exit 0
