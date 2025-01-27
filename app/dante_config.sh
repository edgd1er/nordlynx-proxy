#!/bin/bash
set -e -u -o pipefail

##Functions
source /app/utils.sh
SOURCE_DANTE_CONF=/etc/danted.conf.tmpl
DANTE_CONF=/etc/sockd.conf
DANTE_DEBUG=${DANTE_DEBUG:-0}
DANTE_LOGLEVEL=${DANTE_LOGLEVEL:-"error"}
INTERFACE=$(ifconfig | grep -oE "(nordtun|nordlynx)")
DANTE_LOGLEVEL=${DANTE_LOGLEVEL//\"/}
DANTE_LOGOUTPUT=${DANTE_LOGOUTPUT//\"/}

log "INFO: DANTE: INTERFACE: ${INTERFACE}, error log: ${DANTE_LOGOUTPUT}, log level: ${DANTE_LOGLEVEL}, dante debug: ${DANTE_DEBUG}"
sed "s/INTERFACE/${INTERFACE}/" ${SOURCE_DANTE_CONF} >${DANTE_CONF}
sed -i "s/#clientmethod: none/clientmethod: none/" ${DANTE_CONF}
sed -i "s/DANTE_DEBUG/${DANTE_DEBUG}/" ${DANTE_CONF}
sed -i "s/log: error/log: ${DANTE_LOGLEVEL}/g" ${DANTE_CONF}

#define logoutput
if [[ "file" == ${DANTE_LOGOUTPUT} ]]; then
  echo "Setting dante log to /var/log/dante.log"
  sed -i -r "s%^#?logoutput: DANTE_LOGOUTPUT%logoutput: /var/log/dante.log%" ${DANTE_CONF}
else
  echo "Settting dante log to stdout"
  sed -i -r "s%^#?logoutput: DANTE_LOGOUTPUT%logoutput: stdout%" ${DANTE_CONF}
fi


#basic Auth
TCREDS_SECRET_FILE=/run/secrets/TINY_CREDS
if [[ -f ${TCREDS_SECRET_FILE} ]]; then
  TINYUSER=$(head -1 ${TCREDS_SECRET_FILE})
  TINYPASS=$(tail -1 ${TCREDS_SECRET_FILE})
fi
if [[ -n ${TINYUSER:-''} ]] && [[ -n ${TINYPASS:-''} ]]; then
  createUserForAuthifNeeded ${TINYUSER}
  echo "${TINYUSER}:${TINYPASS}" | chpasswd
  sed -i -r "s/#?socksmethod: .*/socksmethod: username/" ${DANTE_CONF}
else
  sed -i -r "s/#?socksmethod: .*/socksmethod: none/" ${DANTE_CONF}
fi

#Allow from private addresses from clients
if [[ -n ${LOCAL_NETWORK:-''} ]]; then
  aln=(${LOCAL_NETWORK//,/ })
  msg=""
  for l in ${aln[*]}; do
    echo "client pass {
        from: ${l} to: 0.0.0.0/0
	log: error
}" >>${DANTE_CONF}
  done
else
  #no local network defined, allowing known private addresses.
  echo "#Allow private addresses from clients
client pass {
        from: 10.0.0.0/8 to: 0.0.0.0/0
  log: error
}

client pass {
        from: 172.16.0.0/12 to: 0.0.0.0/0
	log: error
}

client pass {
        from: 192.168.0.0/16 to: 0.0.0.0/0
	log: error
}" >>${DANTE_CONF}
fi

#Allow local access + eth0 network
echo "client pass {
        from: 127.0.0.0/8 to: 0.0.0.0/0
	log: error
}

client pass {
        from: $(getEthCidr) to: 0.0.0.0/0
	log: error
}

#Allow all sockets connections
socks pass {
        from: 0.0.0.0/0 to: 0.0.0.0/0
        protocol: tcp udp
        log: error
}
" >>${DANTE_CONF}

[[ -n ${DANTE_LOGLEVEL} ]] && sed -i "s/log: error/log: ${DANTE_LOGLEVEL}/" ${DANTE_CONF}
#[[ -n ${DANTE_ERRORLOG} ]] && sed -i "s#errorlog: /dev/null#errorlog: ${DANTE_ERRORLOG}#" ${DANTE_CONF}

log "INFO: DANTE: check configuration socks proxy"
danted -Vf ${DANTE_CONF}
