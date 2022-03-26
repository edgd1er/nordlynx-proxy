#!/bin/bash

set -u -o pipefail

RDIR=/run/nordvpn
DEBUG=${DEBUG:-0}
COUNTRY=${COUNTRY:-''}
CONNECT=${CONNECT:-''}
GROUP=${GROUP:-''}
IPV6=${IPV6:-'off'}
[[ -n ${COUNTRY} && -z ${CONNECT} ]] && export CONNECT=${COUNTRY}
[[ "${GROUPID:-''}" =~ ^[0-9]+$ ]] && groupmod -g $GROUPID -o vpn
[[ -n ${GROUP} ]] && GROUP="--group ${GROUP}"
#get container network (class B) to whitelist container subnet:  ${LOCALNET}.0.0/16
LOCALNET=$(hostname -i | grep -Eom1 "(^[0-9]{1,3}\.[0-9]{1,3})")

[[ "true" == ${DEBUG} ]] && export DEBUG=1 || true

if [[ 1 -eq ${DEBUG} ]]; then
  set -x
  #set DANTE_DEBUG only if not already set
  [[ -z ${DANTE_DEBUG:-''} ]] && export DANTE_DEBUG=9
else
  #set DANTE_DEBUG onl if not already set
  DANTE_DEBUG=${DANTE_DEBUG:-0}
fi

. /app/date.sh --source-only

##Functions
setTimeZone() {
  [[ ${TZ} == $(cat /etc/timezone) ]] && return
  log "INFO: Setting timezone to ${TZ}"
  ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime
  dpkg-reconfigure -fnoninteractive tzdata
}

set_iptables() {
  action=${1:-'DROP'}
  log "INFO: setting iptables policy to ${action}"
  iptables -F
  iptables -X
  iptables -P INPUT ${action}
  iptables -P FORWARD ${action}
  iptables -P OUTPUT ${action}
}

setIPV6() {
  if [[ 0 -eq $(grep -c "net.ipv6.conf.all.disable_ipv6" /etc/sysctl.conf) ]]; then
    echo "net.ipv6.conf.all.disable_ipv6 = ${1}" >/etc/sysctl.conf
  else
    sed -i -E "s/net.ipv6.conf.all.disable_ipv6 = ./net.ipv6.conf.all.disable_ipv6 = ${1}/" /etc/sysctl.conf
  fi
  sysctl -p || true
}

checkLatest() {
  res=$(curl -ks https://nordvpn.com/en/blog/nordvpn-linux-release-notes/)
  [[ -z $res ]] && return 1
  CANDIDATE=$(echo ${res} | grep -oP "NordVPN \K[0-9]\.[0-9]{1,2}" | head -1)
  [[ "" == ${CANDIDATE} ]] && return 1
  VERSION=$(nordvpn version | grep -oP "NordVPN Version \K.+")
  if [[ ${VERSION} =~ ${CANDIDATE} ]]; then
    log "INFO: No update needed for nordvpn (${VERSION})"
  else
    log "**********************************************************************"
    log "WARNING: please update nordvpn from version ${VERSION} to ${CANDIDATE}"
    log "WARNING: please update nordvpn from version ${VERSION} to ${CANDIDATE}"
    log "**********************************************************************"
  fi
}

checkLatestApt() {
  apt-get update
  VERSION=$(apt-cache policy nordvpn | grep -oP "Installed: \K.+")
  CANDIDATE=$(apt-cache policy nordvpn | grep -oP "Candidate: \K.+")
  CANDIDATE=${CANDIDATE:-${VERSION}}
  if [[ ${CANDIDATE} != ${VERSION} ]]; then
    log "**********************************************************************"
    log "WARNING: please update nordvpn from version ${VERSION} to ${CANDIDATE}"
    log "WARNING: please update nordvpn from version ${VERSION} to ${CANDIDATE}"
    log "**********************************************************************"
  else
    log "INFO: No update needed for nordvpn (${VERSION})"
  fi
}

#embedded in nordvpn client but not efficient in container. done in docker-compose
#setIPV6 ${IPV6}

setup_nordvpn() {
  nordvpn set technology ${TECHNOLOGY:-'NordLynx'}
  nordvpn set cybersec ${CYBER_SEC:-'off'}
  nordvpn set killswitch ${KILLERSWITCH:-'on'}
  nordvpn set ipv6 ${IPV6} 2>/dev/null
  [[ -n ${DNS:-''} ]] && nordvpn set dns ${DNS//[;,]/ }
  [[ -z ${DOCKER_NET:-''} ]] && DOCKER_NET="$(hostname -i | grep -Eom1 "^[0-9]{1,3}\.[0-9]{1,3}").0.0/12"
  nordvpn whitelist add subnet ${DOCKER_NET}
  [[ -n ${NETWORK:-''} ]] && for net in ${NETWORK//[;,]/ }; do nordvpn whitelist add subnet ${net}; done
  [[ -n ${PORTS:-''} ]] && for port in ${PORTS//[;,]/ }; do nordvpn whitelist add port ${port}; done
  [[ ${DEBUG} ]] && nordvpn -version && nordvpn settings
  nordvpn whitelist add subnet ${LOCALNET}.0.0/16
  if [[ -n ${LOCAL_NETWORK:-''} ]]; then
    nordvpn whitelist add subnet ${LOCAL_NETWORK}
    eval $(/sbin/ip route list match 0.0.0.0 | awk '{if($5!="tun0"){print "GW="$3"\nINT="$5; exit}}')
    echo "LOCAL_NETWORK: ${LOCAL_NETWORK}, Gateway: ${GW}, device ${INT}"
    if [[ -n ${GW:-""} ]] && [[ -n ${INT:-""} ]]; then
      for localNet in ${LOCAL_NETWORK//,/ }; do
        echo "adding route to local network ${localNet} via ${GW} dev ${INT}"
        /sbin/ip route add "${localNet}" via "${GW}" dev "${INT}"
      done
    fi
  else
    log "OPENVPN: undefined LOCAL_NETWORK, sockd and http proxies available only through 127.0.0.1 or 0.0.0.0"
  fi
}

mkTun(){
# Create a tun device see: https://www.kernel.org/doc/Documentation/networking/tuntap.txt
if [ ! -c /dev/net/tun ]; then
    log "INFO: OVPN: Creating tun interface /dev/net/tun"
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200
    chmod 600 /dev/net/tun
fi
}

#Main
#Overwrite docker dns as it may fail with specific configuration (dns on server/container crash)
echo "nameserver 1.1.1.1" >/etc/resolv.conf
setTimeZone


#log all if required: IPTABLES_LOG=1
if [[ -f /app/logAll.sh ]]; then
  /app/logAll.sh
else
  log "INFO: logall feature not availablebmw
  "
fi
#exit if required vars are missing
[[ -z ${CONNECT} ]] && exit 1
[[ ! -d ${RDIR} ]] && mkdir -p ${RDIR}

#make /dev/tun if missing
mkTun
set_iptables DROP
set_iptables ACCEPT

log "INFO: NORDVPN: starting nordvpn daemon"
action=start
isRunning=$(supervisorctl status nordvpnd | grep -c RUNNING) || true
[[ 0 -le ${isRunning} ]] && action=restart
supervisorctl ${action} nordvpnd
sleep 4
#need daemon to be up, check if installed nordvpn app is the latest available
checkLatest
[[ 1 -eq $? ]]  && checkLatestApt
#start nordvpn daemon
while [ ! -S ${RDIR}/nordvpnd.sock ]; do
  log "WARNING: NORDVPN: restart nordvpn daemon as no socket was found"
  supervisorctl restart nordvpnd
  sleep 4
done

#Use secrets if present
#Use secrets if present
set +x
if [ -e /run/secrets/NORDVPN_CREDS ]; then
  NORDVPN_LOGIN=$(head -1 /run/secrets/NORDVPN_CREDS)
  NORDVPN_PASS=$(tail -1 /run/secrets/NORDVPN_CREDS)
  [[ "${NORDVPN_LOGIN}" == "${NORDVPN_PASS}" ]] && log "ERROR, credentials shoud have two lines (login/password), one found." && exit
fi

if [ -z ${NORDVPN_LOGIN} ] || [ -z ${NORDVPN_PASS} ]; then
  log "ERROR: NORDVPN: **********************"
  log "ERROR: NORDVPN: empty user or password"
  log "ERROR: NORDVPN: **********************"
  exit 1
fi

# login: already logged in return 1
res=$(nordvpn login --username ${NORDVPN_LOGIN} --password "${NORDVPN_PASS}" || true)
if [[ "${res}" != *"Welcome to NordVPN"* ]] && [[ "${res}" != *"You are already logged in."* ]]; then
  log "ERROR: NORDVPN: cannot login: ${res}"
  exit 1
fi
log "INFO: NORDVPN: logged in: ${res}"

#define connection parameters
setup_nordvpn
log "INFO: NORDVPN: connecting to ${GROUP} ${CONNECT} "

#connect to vpn
res=$(nordvpn connect ${GROUP} ${CONNECT}) || true
log "INFO: NORDVPN: connect: ${res}"
if [[ "${res}" != *"You are connected to"* ]]; then
  log "ERROR: NORDVPN: cannot connect to ${GROUP} ${CONNECT}"
  res=$(nordvpn connect ${CONNECT}) || true
  log "INFO: NORDVPN: connecting to ${CONNECT}"
  [[ "${res}" != *"You are connected to"* ]] && log "ERROR: NORDVPN: cannot connect to ${CONNECT}" && exit 1
fi
nordvpn status

log "INFO: current WAN IP: $(curl -s 'https://api.ipify.org?format=json' | jq .ip)"

log "INFO: DANTE: generate configuration"
/app/dante_config.sh

log "INFO: TINYPROXY: generate configuration"
/app/tinyproxy_config.sh

#check N times for connected status
N=10
while [[ $(nordvpn status | grep -ic "connected") -eq 0 ]]; do
  sleep 3
  N--
  [[ ${N} -eq 0 ]] && log "ERROR: NORDVPN: cannot connect" && exit 1
done

log "INFO: DANTE: starting"
supervisorctl start dante
sleep 2
log "INFO: TINYPROXY: starting"
supervisorctl start tinyproxy

