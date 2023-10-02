#!/bin/bash

#########################
# HELP
#########################

export DEBIAN_FRONTEND=noninteractive

log() {
  echo \["$(date +%Y/%m/%d-%H:%M:%S)"\] "$1"
  echo \["$(date +%Y/%m/%d-%H:%M:%S)"\] "$1" >>/var/log/nebula-exchange-install.log
}

log "Begin execution of NebulaGraph Exchange script extension on ${HOSTNAME}"

#########################
# Preconditions
#########################

EXCHANGE_VERSION=${1:-"3.0.0"}
EXCHANGE_PATH="/usr/local/nebula-exchange-deps-${EXCHANGE_VERSION}"

#########################
# Installation steps as functions
#########################
install_exchange_deps() {
  local PACKAGE="nebula-exchange-deps-${EXCHANGE_VERSION}.tar.gz"

  log "[install_exchange_deps] exchange version ${EXCHANGE_VERSION} "
  log "[install_exchange_deps] spark version 2.4"
  log "[install_exchange_deps] jdk 1.8"
  log "[install_exchange_deps] scala 2.12.11"

  chmod +x nebula-download
  ./nebula-download exchange --version="${EXCHANGE_VERSION}"

  local EXIT_CODE=$?
  if [ ${EXIT_CODE} -ne 0 ]; then
    log "[install_exchange_deps] error downloading NebulaGraph Exchange ${EXCHANGE_VERSION} and its deps"
    exit ${EXIT_CODE}
  fi

  tar -zxvf "${PACKAGE}" -C /usr/local
  log "[install_exchange_deps] installed Exchange ${EXCHANGE_VERSION} and its deps"
}

configure_jdk() {
  log "[configure_jdk] start to configure jdk"
  local JAVA_DIR="/usr/local/java"
  local JDK="jdk1.8.0_202"
  local JAVA_HOME="${JAVA_DIR}/${JDK}"
  local PROFILE="/etc/profile"
  mkdir -p "${JAVA_DIR}"
  mv "${EXCHANGE_PATH}/${JDK}" "${JAVA_DIR}"
  {
    echo "export JAVA_HOME=${JAVA_DIR}/${JDK}"
    echo "export CLASSPATH=.:${JAVA_HOME}/lib/dt.jar:${JAVA_HOME}/lib/tools.jar:${JAVA_HOME}/jre/lib"
    echo "export PATH=${PATH}:${JAVA_HOME}/bin"
  } >>${PROFILE}
  # shellcheck source=/etc/profile disable=SC1091
  source ${PROFILE}
  ln -sf "${JAVA_HOME}/bin/java" /usr/bin/java
  java -version
  local EXIT_CODE=$?
  if [ ${EXIT_CODE} -ne 0 ]; then
    log "[configure_jdk] failed to configure jdk"
    exit ${EXIT_CODE}
  fi
  log "[configure_jdk] finished to configure jdk"
}

configure_scala() {
  log "[configure_scala] start to configure scala"
  local SCALA_DIR="/usr/local/scala"
  local SCALA_SDK="scala-2.12.11"
  local SCALA_HOME="${SCALA_DIR}/${SCALA_SDK}"
  local PROFILE="/etc/profile"
  mkdir -p ${SCALA_DIR}
  mv "${EXCHANGE_PATH}/${SCALA_SDK}" ${SCALA_DIR}
  {
    echo "export SCALA_HOME=${SCALA_DIR}/${SCALA_SDK}"
    echo "export PATH=${PATH}:${SCALA_HOME}/bin"
  } >>${PROFILE}
  # shellcheck source=/etc/profile disable=SC1091
  source ${PROFILE}
  ln -sf "${SCALA_HOME}/bin/scala" /usr/bin/scala
  scala -version
  local EXIT_CODE=$?
  if [ ${EXIT_CODE} -ne 0 ]; then
    log "[configure_scala] failed to configure scala"
    exit ${EXIT_CODE}
  fi
  log "[configure_scala] finished to configure scala"
}

# only all-in-one version support, distribution version needs to deploy by user self
configure_and_deploy_spark() {
  log "[configure_and_deploy_spark] start to configure spark"
  local SPARK_RESOURCE="spark-2.4.8-bin-hadoop2.7"
  local SPARK_HOME="/usr/local/${SPARK_RESOURCE}"
  mv "${EXCHANGE_PATH}/${SPARK_RESOURCE}" /usr/local/

  local PROFILE="/etc/profile"
  {
    echo "export SPARK_HOME=/usr/local/${SPARK_RESOURCE}"
    echo "export PATH=${PATH}:${SPARK_HOME}/bin:${SPARK_HOME}/sbin"
  } >>${PROFILE}
  # shellcheck source=/etc/profile disable=SC1091
  source ${PROFILE}
  log "[configure_and_deploy_spark] start to deploy spark"

  /usr/local/${SPARK_RESOURCE}/sbin/start-all.sh
  jps
  local EXIT_CODE=$?
  if [ ${EXIT_CODE} -ne 0 ]; then
    log "[configure_and_deploy_spark] failed to deploy spark"
    exit ${EXIT_CODE}
  fi
  log "[configure_and_deploy_spark] finished to deploy spark"
}

install_exchange_deps
configure_jdk
configure_scala
configure_and_deploy_spark

log "End execution of NebulaGraph Exchange script extension on ${HOSTNAME}"
exit 0
