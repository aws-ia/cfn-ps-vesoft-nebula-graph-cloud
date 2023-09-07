#!/bin/bash

#########################
# HELP
#########################

export DEBIAN_FRONTEND=noninteractive

help() {
  echo "This script installs NebulaGraph Dashboard on Ubuntu"
  echo ""
  echo "Options:"
  echo "    -v      nebula dashboard version, default: 3.4.0"
  echo "    -g      nebula graph ips, seperated by comma,"
  echo "    -m      nebula meta ips, seperated by comma,"
  echo "    -s      nebula storage ips, seperated by comma,"
  echo "    -k      ssh private key"
  echo "    -h      view default help content"
}

log() {
  echo \["$(date +%Y/%m/%d-%H:%M:%S)"\] "$1"
  echo \["$(date +%Y/%m/%d-%H:%M:%S)"\] "$1" >>/var/log/nebula-dashboard-install.log
}

log "Begin execution of NebulaGraph Dashboard script extension on ${HOSTNAME}"
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

DASHBOARD_VERSION="3.4.0"
DASHBOARD_PATH="/usr/local/nebula-dashboard-ent"
NEBULA_LICENSE_PATH="${DASHBOARD_PATH}/nebula.license"
SYSTEMD_PATH="/usr/lib/systemd/system"

#Loop through options passed
while getopts :v:g:m:s:k:l:h optname; do
  log "Option ${optname} set"
  case $optname in
    v) #set nebula version
      DASHBOARD_VERSION="${OPTARG}"
      ;;
    g) #set nebula graph ips
      NEBULA_GRAPH_IPS="${OPTARG}"
      ;;
    m) #set nebula meta ips
      NEBULA_META_IPS="${OPTARG}"
      ;;
    s) #set nebula storage ips
      NEBULA_STORAGE_IPS="${OPTARG}"
      ;;
    k) #set ssh private key
      SSH_PRIVATE_KEY="${OPTARG}"
      ;;
    l) #set license link
      LICENSE_LINK="${OPTARG}"
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
#Define systemctl units
#########################

ALERT_MANAGER_SERVICE="[Unit]
Description=Nebula Dashboard Alert Manager
After=network.target

[Service]
Type=forking
Restart=always
RestartSec=10s
PIDFile=$DASHBOARD_PATH/pids/alertmanager.pid
ExecStart=$DASHBOARD_PATH/scripts/dashboard.service start alertmanager
ExecReload=$DASHBOARD_PATH/scripts/dashboard.service restart alertmanager
ExecStop=$DASHBOARD_PATH/scripts/dashboard.service stop alertmanager

[Install]
WantedBy=multi-user.target"

PROMETHEUS_SERVICE="[Unit]
Description=Nebula Dashboard Prometheus
After=network.target

[Service]
Type=forking
Restart=always
RestartSec=10s
PIDFile=$DASHBOARD_PATH/pids/prometheus.pid
ExecStart=$DASHBOARD_PATH/scripts/dashboard.service start prometheus
ExecReload=$DASHBOARD_PATH/scripts/dashboard.service restart prometheus
ExecStop=$DASHBOARD_PATH/scripts/dashboard.service stop prometheus

[Install]
WantedBy=multi-user.target"

WEBSERVER_SERVICE="[Unit]
Description=Nebula Dashboard Prometheus
After=network.target

[Service]
Type=forking
Restart=always
RestartSec=10s
PIDFile=$DASHBOARD_PATH/pids/webserver.pid
ExecStart=$DASHBOARD_PATH/scripts/dashboard.service start webserver
ExecReload=$DASHBOARD_PATH/scripts/dashboard.service restart webserver
ExecStop=$DASHBOARD_PATH/scripts/dashboard.service stop webserver

[Install]
WantedBy=multi-user.target"

#########################
# Installation steps as functions
#########################

# Install NebulaGraph Dashboard
install_dashboard() {
  local PACKAGE="nebula-dashboard-ent-${DASHBOARD_VERSION}.linux-amd64.tar.gz"

  log "[install_dashboard] installing NebulaGraph Dashboard ${DASHBOARD_VERSION}"

  chmod +x nebula-download
  if [ -z "${LICENSE_LINK}" ]; then
     ./nebula-download dashboard --version="${DASHBOARD_VERSION}" --trial
  else
     ./nebula-download dashboard --version="${DASHBOARD_VERSION}"
  fi

  local EXIT_CODE=$?
  if [ $EXIT_CODE -ne 0 ]; then
    log "[install_dashboard] error downloading NebulaGraph Dashboard $DASHBOARD_VERSION"
    exit $EXIT_CODE
  fi

  tar -xvf "$PACKAGE" -C /usr/local

  log "[install_dashboard] installed NebulaGraph Dashboard $DASHBOARD_VERSION"
}

# Security
configure_license() {
  log "[configure_license] save license to file"
  cp nebula-dashboard.license $NEBULA_LICENSE_PATH
}

register_systemd() {
  log "[register_systemd] configure systemd to start Dashboard service automatically when system boots"
  local ALERT_MANAGER_UNIT="nbd-alert-manager.service"
  local PROMETHEUS_UNIT="nbd-prometheus.service"
  local WEBSERVER_UNIT="nbd-webserver.service"

  echo "${ALERT_MANAGER_SERVICE}" >"${SYSTEMD_PATH}"/${ALERT_MANAGER_UNIT}
  echo "${PROMETHEUS_SERVICE}" >"${SYSTEMD_PATH}"/${PROMETHEUS_UNIT}
  echo "${WEBSERVER_SERVICE}" >"${SYSTEMD_PATH}"/${WEBSERVER_UNIT}

  UNIT_NAMES=("${ALERT_MANAGER_UNIT}" "${PROMETHEUS_UNIT}" "${WEBSERVER_UNIT}")
  for UNIT_NAME in "${UNIT_NAMES[@]}"; do
    systemctl daemon-reload
    systemctl enable "${UNIT_NAME}"
  done
}

start_dashboard() {
  log "[start_dashboard] starting Dashboard"
  UNIT_NAMES=(nbd-alert-manager.service nbd-prometheus.service nbd-webserver.service)
  for UNIT_NAME in "${UNIT_NAMES[@]}"; do
    systemctl start "${UNIT_NAME}"
  done
  log "[start_dashboard] started Dashboard"

  sleep 5
  fuser 7005/tcp
  local EXIT_CODE=$?
  if [ $EXIT_CODE -ne 0 ]; then
    log "[start_dashboard] start dashboard failed: $EXIT_CODE"
    exit $EXIT_CODE
  fi

  log "[start_dashboard] start dashboard succeed"
}

import_cluster() {
  cat <<EOF >cluster.json
{
  "name": "nebulagraph_aws",
  "vesion": "v$DASHBOARD_VERSION",
  "nebulaType": "enterprise",
  "machines": [],
  "graphd": [],
  "metad": [],
  "storaged": []
}
EOF

  apt install jq -y

  graph_ips=$(echo "$NEBULA_GRAPH_IPS" | tr "," " ")
  meta_ips=$(echo "$NEBULA_META_IPS" | tr "," " ")
  storage_ips=$(echo "$NEBULA_STORAGE_IPS" | tr "," " ")
  machines=("${graph_ips[*]}" "${meta_ips[*]}" "${storage_ips[*]}")

  cluster=$(jq . cluster.json)
  for ip in ${graph_ips[*]}; do
    cluster="$(jq --arg host "$ip" '.graphd += [{"host": $host, "port": 9669, "httpPort": 19669}]' <<<"$cluster")"
  done
  for ip in ${meta_ips[*]}; do
    cluster="$(jq --arg host "$ip" '.metad += [{"host": $host, "port": 9559, "httpPort": 19559}]' <<<"$cluster")"
  done
  for ip in ${storage_ips[*]}; do
    cluster="$(jq --arg host "$ip" '.storaged += [{"host": $host, "port": 9779, "httpPort": 19779}]' <<<"$cluster")"
  done
  for ip in ${machines[*]}; do
    cluster="$(jq --arg host "$ip" --arg key "$SSH_PRIVATE_KEY" '.machines += [{"host": $host, "sshUser": "ec2-user", "sshKey": $key, "sshType": "key", "sshPort": 22}]' <<<"$cluster")"
  done

  log "$cluster"
  echo "$cluster" >cluster.json

  log "[import_cluster] waiting for nebula cluster ready"
  sleep 100
  log "[import_cluster] importing cluster"
  login_resp=$(curl -sS -X POST -H "Content-type: application/json" -d '{"username": "nebula", "password": "nebula", "type": "admin"}' http://127.0.0.1:7005/api/v1/account/login)
  login_code=$(echo "${login_resp}" | jq '.code')
  if [ "$login_code" -eq 0 ]; then
    token=$(echo "${login_resp}" | jq '.data.token' | sed 's/"//g')
    import_resp=$(curl -sS -X POST -H "Content-type: application/json" -H "Authorization: Bearer $token" -d "@cluster.json" http://127.0.0.1:7005/api/v1/clusters/import)
    import_code=$(echo "${import_resp}" | jq '.code')
    if [ "$import_code" -ne 0 ]; then
      log "[import_cluster] import cluster returned non-zero code: $import_code"
      exit 1
    fi
  else
    log "[import_cluster] login dashboard returned non-zero code: $login_code"
    exit 1
  fi
  log "[import_cluster] import cluster succeed"
}

#########################
# Installation sequence
#########################

# if dashboard is already installed assume default is a redeploy
if systemctl -q is-active nebula-dashboard.service; then
  log "[dashboard] dashboard service is already active"
  exit 0
fi

install_dashboard

configure_license

register_systemd

start_dashboard

#import_cluster

ELAPSED_TIME=$((SECONDS - START_TIME))
PRETTY=$(printf '%dh:%dm:%ds\n' $((ELAPSED_TIME / 3600)) $((ELAPSED_TIME % 3600 / 60)) $((ELAPSED_TIME % 60)))

log "End execution of NebulaGraph Dashboard script extension on ${HOSTNAME} in ${PRETTY}"
exit 0
