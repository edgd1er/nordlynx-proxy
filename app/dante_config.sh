#!/bin/bash
set -e -u -o pipefail

SOURCE_DANTE_CONF=/etc/danted.conf.tmpl
DANTE_CONF=/etc/sockd.conf
DANTE_DEBUG=${DANTE_DEBUG:-0}
DEBUG=${DEBUG:-0}
DANTE_LOGLEVEL=${DANTE_LOGLEVEL:-""}
DANTE_ERRORLOG=${DANTE_ERRORLOG:-"Error"}
INTERFACE=$(ifconfig | grep -oE "(tun|nordlynx)")
[[ 1 -eq ${DEBUG} ]] && [[ 0 -eq ${DANTE_DEBUG} ]] && DANTE_DEBUG=" 9" && set -x
DANTE_LOGLEVEL=${DANTE_LOGLEVEL//\"/}
DANTE_ERRORLOG=${DANTE_ERRORLOG//\"/}

. /app/date.sh --source-only
log "INFO: DANTE: INTERFACE: ${INTERFACE}, error log: ${DANTE_ERRORLOG}, log level: ${DANTE_LOGLEVEL}, dante debug: ${DANTE_DEBUG}"
sed "s/INTERFACE/${INTERFACE}/" ${SOURCE_DANTE_CONF} > ${DANTE_CONF}
sed -i "s/DANTE_DEBUG/${DANTE_DEBUG}/" ${DANTE_CONF}
sed -i "s/#clientmethod: none/clientmethod: none/" ${DANTE_CONF}
sed -i "s/#socksmethod: none/socksmethod: none/" ${DANTE_CONF}
[[ -n ${DANTE_LOGLEVEL} ]] && sed -i "s/log: error/log: ${DANTE_LOGLEVEL}/" ${DANTE_CONF}
[[ -n ${DANTE_ERRORLOG} ]] && sed -i "s#errorlog: /dev/null#errorlog: ${DANTE_ERRORLOG}#" ${DANTE_CONF}
log "INFO: DANTE: check configuration socks proxy"
danted -Vf  ${DANTE_CONF}
