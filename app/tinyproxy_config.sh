#!/usr/bin/env bash
set -e -u -o pipefail

#Variables
DEBUG=${DEBUG:-0}
[[ 1 -eq ${DEBUG} ]] && set -x
. /app/date.sh --source-only
SOURCE_CONF=/etc/tinyproxy.conf.tmpl
CONF=/etc/tinyproxy/tinyproxy.conf
TINYPORT=${TINYPORT:-8888}
#Critical (least verbose), Error, Warning, Notice, Connect (to log connections without Info's noise), Info
TINYLOGLEVEL=${TINYLOGLEVEL:-Error}
TINYLOGLEVEL=${TINYLOGLEVEL//\"/}
EXT_IP=$(ip -4 a show nordlynx | grep -oP "(?<=inet )([^/]+)")
INT_IP=$(ip -4  a show eth0| grep -oP "(?<=inet )([^/]+)")
INT_CIDR=$(ip -j a show eth0 | jq  -r '.[].addr_info[0]|"\( .local)/\(.prefixlen)"')

#Main
log "INFO: TINYPROXY: set configuration INT_IP: ${INT_IP}/ EXT_IP: ${EXT_IP}"
sed "s/TINYPORT/${TINYPORT}/" ${SOURCE_CONF} > ${CONF}
sed -i "s/TINYLOGLEVEL/${TINYLOGLEVEL}/" ${CONF}
sed -i -r "s/#?Listen/Listen ${INT_IP}/" ${CONF}

sed -i "s!#Allow INT_CIDR!Allow ${INT_CIDR}!" ${CONF}
#Allow only local network or all private address ranges
if [[ -n ${LOCAL_NETWORK:-''} ]];then
    sed -i "s!#Allow LOCAL_NETWORK!Allow ${LOCAL_NETWORK}!" ${CONF}
else
    sed -i "s!#Allow 10!Allow 10!" ${CONF}
    sed -i "s!#Allow 172!Allow 172!" ${CONF}
    sed -i "s!#Allow 192!Allow 192!" ${CONF}
fi

#show Conf
[[ 1 -eq ${DEBUG} ]] && grep -vE "(^#|^$)" ${CONF} || true
