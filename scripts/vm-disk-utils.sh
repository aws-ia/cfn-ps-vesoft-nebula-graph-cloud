#!/bin/bash

#########################
# HELP
#########################

export DEBIAN_FRONTEND=noninteractive

help() {
  echo "This script init disks on Ubuntu"
  echo ""
  echo "Options:"
  echo "   -b         base directory for mount points (default: /usr/local/nebula)"
  echo "   -o         mount options for data disk"
  echo "   -h         default help message"
}

log() {
  echo \["$(date +%Y/%m/%d-%H:%M:%S)"\] "$1"
  echo \["$(date +%Y/%m/%d-%H:%M:%S)"\] "$1" >>/var/log/nebula-install.log
}

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

# Base path for data disk mount points
DATA_BASE="/usr/local/nebula"
# Mount options for data disk
MOUNT_OPTIONS="noatime,nodiratime,nodev,noexec,nosuid,nofail"

while getopts :b:h:o optname; do
  log "Option $optname set with value ${OPTARG}"
  case ${optname} in
    b) #Set base path for data disks
      DATA_BASE=${OPTARG}
      ;;
    o) #mount option
      MOUNT_OPTIONS=${OPTARG}
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

is_partitioned() {
  OUTPUT=$(partx -s "${1}" 2>&1)
  grep -E "failed to read partition table" <<<"${OUTPUT}" >/dev/null 2>&1
  local EXIT_CODE=$?
  if [ $EXIT_CODE -eq 0 ]; then
    return 1
  else
    return 0
  fi
}

has_filesystem() {
  DEVICE=${1}
  OUTPUT=$(file -L -s "${DEVICE}")
  grep filesystem <<<"${OUTPUT}" >/dev/null 2>&1
  return $?
}

add_to_fstab() {
  UUID=${1}
  MOUNTPOINT=${2}
  log "calling fstab with UUID: ${UUID} and mount point: ${MOUNTPOINT}"
  grep "${UUID}" /etc/fstab >/dev/null 2>&1
  local EXIT_CODE=$?
  if [ $EXIT_CODE -eq 0 ]; then
    log "Not adding ${UUID} to fstab again (it's already there!)"
  else
    LINE="UUID=\"${UUID}\"\t${MOUNTPOINT}\text4\t${MOUNT_OPTIONS}\t1 2"
    echo -e "${LINE}" >>/etc/fstab
  fi
}

do_partition() {
  DISK=${1}
  log "create partition for ${DISK} with parted"
  parted -s "${DISK}" -- mklabel gpt mkpart primary 0% 100%
  local EXIT_CODE=$?
  if [ $EXIT_CODE -ne 0 ]; then
    log "An error occurred partitioning ${DISK}"
    echo "An error occurred partitioning ${DISK}" >&2
    echo "I cannot continue" >&2
    exit $EXIT_CODE
  fi
}

scan_partition_format() {
  DISK=${1}
  log "Working on ${DISK}"
  is_partitioned "${DISK}"
  local EXIT_CODE=$?
  if [ $EXIT_CODE -ne 0 ]; then
    log "${DISK} is not partitioned, partitioning"
    do_partition "${DISK}"
  fi
  PARTITION=$(fdisk -l "${DISK}" | grep -A 1 Device | tail -n 1 | awk '{print $1}')
  has_filesystem "${PARTITION}"
  if [ $EXIT_CODE -ne 0 ]; then
    log "Creating filesystem on ${PARTITION}."
    # echo "Press Ctrl-C if you don't want to destroy all data on ${PARTITION}"
    # sleep 10
    mkfs -j -t ext4 "${PARTITION}"
  fi
  MOUNTPOINT="${DATA_BASE}/disk1"
  [ -d "${MOUNTPOINT}" ] || mkdir -p "${MOUNTPOINT}"
  read UUID FS_TYPE < <(blkid -u filesystem "${PARTITION}" | awk -F "[= ]" '{print $3" "$5}' | tr -d "\"")
  add_to_fstab "${UUID}" "${MOUNTPOINT}"
  log "Mounting disk ${PARTITION} on ${MOUNTPOINT}"
  mount -t ext4 "${PARTITION}" "${MOUNTPOINT}"
}

#########################
# Create Partitions sequence
#########################

scan_partition_format "/dev/nvme1n1"
exit 0
