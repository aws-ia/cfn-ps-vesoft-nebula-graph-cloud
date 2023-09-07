#!/bin/bash

#########################
# HELP
#########################

export DEBIAN_FRONTEND=noninteractive

help() {
  echo "This script installs NebulaGraph on Ubuntu"
  echo ""
  echo "Options:"
  echo "    -v      nebula version, default: 3.4.0"
  echo "    -c      nebula component, default: all"
  echo "    -m      nebula meta_server_address, default: 127.0.0.1:9559"
  echo "    -i      nebula component index, only used for storaged now, default: 1"
  echo "    -l      nebula license link, default empty and will provide a trial license"

  echo "    -h      view default help content"
}

log() {
  echo \["$(date +%Y/%m/%d-%H:%M:%S)"\] "$1"
  echo \["$(date +%Y/%m/%d-%H:%M:%S)"\] "$1" >>/var/log/nebula-install.log
}

log "Begin execution of NebulaGraph script extension on ${HOSTNAME}"
log "$@"
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
HOST_INDEX=1

NEBULA_VERSION="3.4.0"
NEBULA_COMPONENT="all"
NEBULA_LICENSE_PATH="/usr/local/nebula/share/resources/nebula.license"

#LOCAL_IP=$(ip addr | awk /"$(ip route | awk '/default/ { print $5 }')"/ | awk '/inet/ { print $2 }' | cut -f 1 -d "/")
LOCAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
META_SERVER_ADDRESS="${LOCAL_IP}:9559"

FLAG_LOCAL_IP="--local_ip"
FLAG_META_SERVER_ADDRESS="--meta_server_addrs"
FLAG_DATA_PATH="--data_path"
FLAG_LOG_PATH="--log_dir"

MOUNTPOINT="/usr/local/nebula/disk1"
DISK_DATA_PATH="/usr/local/nebula/data"
DISK_LOG_PATH="/usr/local/nebula/logs"

SYSTEMD_PATH="/usr/lib/systemd/system"

#Loop through options passed
while getopts :v:c:m:i:l:h optname; do
  log "Option ${optname} set"
  case $optname in
    v) #set nebula version
      NEBULA_VERSION="${OPTARG}"
      ;;
    c) #set nebula component
      NEBULA_COMPONENT="${OPTARG}"
      ;;
    m) #set meta_server_address
      META_SERVER_ADDRESS="${OPTARG}"
      ;;
    i) #set component index
      HOST_INDEX="${OPTARG}"
      ;;
    l) #set license link
      LICENSE_LINK="${OPTARG}"
      ;;
    h) #show help
      help
      exit 2
      ;;
    \?) #unrecognized option - show help
      echo -e \\n"Option -${OPTARG} not allowed."
      help
      exit 2
      ;;
  esac
done

#########################
#Define systemctl units
#########################

GRAPHD_SERVICE="[Unit]
Description=NebulaGraph Graphd Service
After=network.target

[Service]
Type=forking
Restart=always
RestartSec=30s
PIDFile=/usr/local/nebula/pids/nebula-graphd.pid
ExecStart=/usr/local/nebula/scripts/nebula.service start graphd
ExecReload=/usr/local/nebula/scripts/nebula.service restart graphd
ExecStop=/usr/local/nebula/scripts/nebula.service stop graphd
PrivateTmp=true
LimitNOFILE=60000

[Install]
WantedBy=multi-user.target"

METAD_SERVICE="[Unit]
Description=NebulaGraph Metad Service
After=network.target

[Service]
Type=forking
Restart=always
RestartSec=60s
PIDFile=/usr/local/nebula/pids/nebula-metad.pid
ExecStart=/usr/local/nebula/scripts/nebula.service start metad
ExecReload=/usr/local/nebula/scripts/nebula.service restart metad
ExecStop=/usr/local/nebula/scripts/nebula.service stop metad
PrivateTmp=true
LimitNOFILE=10000

[Install]
WantedBy=multi-user.target"

STORAGED_SERVICE="[Unit]
Description=NebulaGraph Storaged Service
After=network.target

[Service]
Type=forking
Restart=always
RestartSec=90s
PIDFile=/usr/local/nebula/pids/nebula-storaged.pid
ExecStart=/usr/local/nebula/scripts/nebula.service start storaged
ExecReload=/usr/local/nebula/scripts/nebula.service restart storaged
ExecStop=/usr/local/nebula/scripts/nebula.service stop storaged
PrivateTmp=true
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target"

#########################
# Installation steps as functions
#########################

# Format data disks (Find data disks then partition, format, and mount them as separate drives)
format_data_disks() {
  log "[format_data_disks] starting partition and format attached disks"
  bash vm-disk-utils.sh
  local EXIT_CODE=$?
  if [ $EXIT_CODE -ne 0 ]; then
    log "[format_data_disks] returned non-zero exit code: $EXIT_CODE"
    exit $EXIT_CODE
  fi
  log "[format_data_disks] finished partition and format attached disks"
}

# Configure NebulaGraph Data Disk Folder and Permissions
setup_data_disk() {
  if [ -d "${MOUNTPOINT}" ]; then
    log "[setup_data_disk] configuring dir ${MOUNTPOINT}"
    DISK_DATA_PATH="${MOUNTPOINT}/data"
    DISK_LOG_PATH="${MOUNTPOINT}/logs"
    mkdir -p "${DISK_DATA_PATH}"
    mkdir -p "${DISK_LOG_PATH}"
  else
    #If we do not find folders/disks in our data disk mount directory then use the defaults
    log "[setup_data_disk] configured data directory does not exist for ${HOSTNAME}. using defaults"
  fi
}

# Install NebulaGraph
install_nebula() {
  local OS_SUFFIX="amd64"
  local OS_VERSION="ubuntu2004"
  local PACKAGE="nebula-graph-ent-${NEBULA_VERSION}.${OS_VERSION}.${OS_SUFFIX}.deb"

  chmod +x nebula-download
  if [ -z "${LICENSE_LINK}" ]; then
    ./nebula-download nebula --version="${NEBULA_VERSION}" --trial
  else
    ./nebula-download nebula --version="${NEBULA_VERSION}"
  fi

  local EXIT_CODE=$?
  if [ $EXIT_CODE -ne 0 ]; then
    log "[install_nebula] error downloading NebulaGraph $NEBULA_VERSION"
    exit $EXIT_CODE
  fi

  dpkg -i --force-architecture "$PACKAGE"

  curl -L -o nebula-console https://github.com/vesoft-inc/nebula-console/releases/download/v3.4.0/nebula-console-linux-amd64-v3.4.0
  chmod +x nebula-console
  cp nebula-console /usr/local/bin/

  log "[install_nebula] installed NebulaGraph $NEBULA_VERSION"
}

# Configure NebulaGraph
configure_nebula() {
  case $NEBULA_COMPONENT in
    "graphd")
      configure_graphd
      ;;
    "metad")
      configure_license
      configure_metad
      ;;
    "storaged")
      if [ "$HOST_INDEX" -lt 4  ] && [ "$NEBULA_COMPONENT" = "storaged" ]; then
        mkdir -p "${DISK_DATA_PATH}/meta"
        configure_license
        configure_metad
      fi
      mkdir -p "${DISK_DATA_PATH}/storage"
      configure_storaged
      ;;
    "all")
      mkdir -p "${DISK_DATA_PATH}/meta"
      mkdir -p "${DISK_DATA_PATH}/storage"
      configure_license
      configure_graphd
      configure_metad
      configure_storaged
      ;;
  esac
}

configure_graphd() {
  log "[configure_graphd] configure nebula-graphd.conf file"
  local GRAPHD_CONF="/usr/local/nebula/etc/nebula-graphd.conf"

  sed -i "s/${FLAG_LOG_PATH}.*/${FLAG_LOG_PATH}=$(echo "${DISK_LOG_PATH}" | sed -e 's/\//\\\//g')/" $GRAPHD_CONF
  configure_common_flag $GRAPHD_CONF
  sed -i "s/--enable_authorize.*/--enable_authorize=true/" "$GRAPHD_CONF"
  sed -i "s/--storage_client_timeout_ms.*/--storage_client_timeout_ms=1200000/" "$GRAPHD_CONF"
}

configure_metad() {
  log "[configure_metad] configure nebula-metad.conf file"
  local METAD_CONF="/usr/local/nebula/etc/nebula-metad.conf"

  sed -i "s/${FLAG_DATA_PATH}.*/${FLAG_DATA_PATH}=$(echo "${DISK_DATA_PATH}/meta" | sed -e 's/\//\\\//g')/" $METAD_CONF
  sed -i "s/${FLAG_LOG_PATH}.*/${FLAG_LOG_PATH}=$(echo "${DISK_LOG_PATH}" | sed -e 's/\//\\\//g')/" $METAD_CONF
  configure_common_flag $METAD_CONF
  sed -i "s/--agent_heartbeat_interval_secs.*/--agent_heartbeat_interval_secs=600/" $METAD_CONF
}

configure_storaged() {
  log "[configure_storaged] configure nebula-storaged.conf file"
  local STORAGED_CONF="/usr/local/nebula/etc/nebula-storaged.conf"

  sed -i "s/${FLAG_DATA_PATH}.*/${FLAG_DATA_PATH}=$(echo "${DISK_DATA_PATH}/storage" | sed -e 's/\//\\\//g')/" $STORAGED_CONF
  sed -i "s/${FLAG_LOG_PATH}.*/${FLAG_LOG_PATH}=$(echo "${DISK_LOG_PATH}" | sed -e 's/\//\\\//g')/" $STORAGED_CONF
  configure_common_flag $STORAGED_CONF
}

add_storaged_hosts() {
  log "[add_storaged_hosts] endpoints: ${META_SERVER_ADDRESS}  hosts: ${LOCAL_IP}"
  sleep 60
  chmod +x hosts-manager
  ./hosts-manager add --endpoints "${META_SERVER_ADDRESS}" --hosts "${LOCAL_IP}"

  local EXIT_CODE=$?
  if [ $EXIT_CODE -ne 0 ]; then
    log "[add_storaged_hosts] failed add storage hosts"
    exit $EXIT_CODE
  fi
}

configure_common_flag() {
  local COMPONENT_CONF=$1

  sed -i "s/${FLAG_LOCAL_IP}.*/${FLAG_LOCAL_IP}=${LOCAL_IP}/" "$COMPONENT_CONF"
  sed -i "s/${FLAG_META_SERVER_ADDRESS}.*/${FLAG_META_SERVER_ADDRESS}=${META_SERVER_ADDRESS}/" "$COMPONENT_CONF"
}

# Security
configure_license() {
  log "[configure_license] save license to file"
  cp nebula.license "${NEBULA_LICENSE_PATH}"
}

# Register NebulaGraph Systemd
register_systemd() {
  case $NEBULA_COMPONENT in
    "graphd")
      register_graph_systemd
      ;;
    "metad")
      register_meta_systemd
      ;;
    "storaged")
      if [ "$HOST_INDEX" -lt 4  ] && [ "$NEBULA_COMPONENT" = "storaged" ]; then
        register_meta_systemd
      fi
      register_storage_systemd
      ;;
    "all")
      register_graph_systemd
      register_meta_systemd
      register_storage_systemd
      ;;
  esac
}

register_graph_systemd() {
  log "[register_graph_systemd] register nebula-graphd service"
  local UNIT_NAME="nebula-graphd.service"

  echo "${GRAPHD_SERVICE}" > ${SYSTEMD_PATH}/${UNIT_NAME}
  systemctl daemon-reload
  systemctl enable ${UNIT_NAME}
}

register_storage_systemd() {
  log "[register_storage_systemd] register nebula-storaged service"
  local UNIT_NAME="nebula-storaged.service"

  echo "${STORAGED_SERVICE}" > ${SYSTEMD_PATH}/${UNIT_NAME}
  systemctl daemon-reload
  systemctl enable ${UNIT_NAME}
}

register_meta_systemd() {
  log "[register_meta_systemd] register nebula-metad service"
  local UNIT_NAME="nebula-metad.service"

  echo "${METAD_SERVICE}" > ${SYSTEMD_PATH}/${UNIT_NAME}
  systemctl daemon-reload
  systemctl enable ${UNIT_NAME}
}

# Start NebulaGraph Systemd
start_nebula() {
  case $NEBULA_COMPONENT in
    "graphd")
      start_graph_systemd
      ;;
    "metad")
      start_meta_systemd
      ;;
    "storaged")
      if [ "$HOST_INDEX" -lt 4  ] && [ "$NEBULA_COMPONENT" = "storaged" ]; then
        start_meta_systemd
      fi
      add_storaged_hosts
      start_storage_systemd
      ;;
    "all")
      start_meta_systemd
      start_graph_systemd
      add_storaged_hosts
      start_storage_systemd
      ;;
  esac
}

start_graph_systemd() {
  log "[start_graph_systemd] starting Nebula Graphd"
  systemctl start nebula-graphd.service
  health_check 19669 Graphd
  log "[start_graph_systemd] started Nebula Graphd"
}

start_meta_systemd() {
  log "[start_meta_systemd] starting Nebula Metad"
  systemctl start nebula-metad.service
  health_check 19559 Metad
  log "[start_meta_systemd] started Nebula Metad"
}

start_storage_systemd() {
  log "[start_storage_systemd] starting Nebula Storaged"
  systemctl start nebula-storaged.service
  health_check 19779 Storaged
  log "[start_storage_systemd] started Nebula Storaged"
}

health_check() {
  declare -i retry=0
  local STATUS_URL="http://${LOCAL_IP}:$1/status"
  sleep 5
  for i in {1..10}; do
    log "[health_check] try $i times"
    curl -sf "${STATUS_URL}"
    local EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
      sleep 5
      retry+=1
    else
      break
    fi
  done
  if [ $retry -eq 10 ]; then
    log "[health_check] start nebula $2 failed"
    exit 1
  fi
}

#########################
# Installation sequence
#########################
format_data_disks

install_nebula

configure_license

setup_data_disk

configure_nebula

register_systemd

start_nebula

ELAPSED_TIME=$((SECONDS - START_TIME))
PRETTY=$(printf '%dh:%dm:%ds\n' $((ELAPSED_TIME / 3600)) $((ELAPSED_TIME % 3600 / 60)) $((ELAPSED_TIME % 60)))

log "End execution of NebulaGraph script extension on ${HOSTNAME} in ${PRETTY}"
exit 0
