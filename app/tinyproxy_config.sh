#!/usr/bin/env bash
set -e -u -o pipefail

#Variables
source /app/utils.sh

SOURCE_CONF=/etc/tinyproxy.conf.tmpl
CONF=/etc/tinyproxy/tinyproxy.conf
TINYPORT=${TINYPORT:-8888}
#Critical (least verbose), Error, Warning, Notice, Connect (to log connections without Info's noise), Info
TINYLOGLEVEL=${TINYLOGLEVEL:-Error}
TINYLOGLEVEL=${TINYLOGLEVEL//\"/}
EXT_IP=$(getExtIp)
INT_IP=$(getEthIp)
INT_CIDR=$(getEthCidr)

#Main
log "INFO: TINYPROXY: set configuration INT_IP: ${INT_IP}/ EXT_IP: ${EXT_IP}"
sed "s/TINYPORT/${TINYPORT}/" ${SOURCE_CONF} >${CONF}
sed -i "s/TINYLOGLEVEL/${TINYLOGLEVEL}/" ${CONF}
sed -i -r "s/#?Listen/Listen ${INT_IP}/" ${CONF}

sed -i "s!#Allow INT_CIDR!Allow ${INT_CIDR}!" ${CONF}
#Allow only local network
if [[ -n ${LOCAL_NETWORK:-''} ]]; then
  aln=(${LOCAL_NETWORK//,/ })
  msg="s%#Allow LOCAL_NETWORK%Allow "
  for l in ${aln[*]}; do
    msg+="${l}\nAllow "
  done
  sed -i "${msg:0:-6}%" ${CONF}
else
  #or all private address ranges, may 10.x.x.x/8 is not a good idea as it is also the vpn range.
  sed -i "s!#Allow 10!Allow 10!" ${CONF}
  sed -i "s!#Allow 172!Allow 172!" ${CONF}
  sed -i "s!#Allow 192!Allow 192!" ${CONF}
fi

#basic Auth
TCREDS_SECRET_FILE=/run/secrets/TINY_CREDS
if [[ -f ${TCREDS_SECRET_FILE} ]]; then
  TINYUSER=$(head -1 ${TCREDS_SECRET_FILE})
  TINYPASS=$(tail -1 ${TCREDS_SECRET_FILE})
fi
if [[ -n ${TINYUSER:-''} ]] && [[ -n ${TINYPASS:-''} ]]; then
  sed -i -r "s/#?BasicAuth user password/BasicAuth ${TINYUSER} ${TINYPASS}/" ${CONF}
  sed -i -r "s/^upstream socks5.*/upstream socks5 danteuser:${TINYPASS}@localhost:1080/g" ${CONF}
else
  sed -i -r "s/^BasicAuth .*/#BasicAuthuser passwordS/" ${CONF}
  sed -i -r "s/^upstream socks5.*/upstream socks5 localhost:1080/g" ${CONF}
fi

#show Conf
[[ 1 -eq ${DEBUG} ]] && grep -vE "(^#|^$)" ${CONF} || true
