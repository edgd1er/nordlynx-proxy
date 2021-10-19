#!/bin/bash

set -eu

RDIR=/run/nordvpn
DEBUG=${DEBUG:-false}
COUNTRY=${COUNTRY:-''}
CONNECT=${CONNECT:-''}
GROUP=${GROUP:-''}
NOIPV6=${NOIPV6:-'off'}
[[ -n ${COUNTRY} && -z ${CONNECT} ]] && CONNECT=${COUNTRY} && export ${CONNECT}
[[ "${GROUPID:-''}" =~ ^[0-9]+$ ]] && groupmod -g $GROUPID -o vpn
[[ -n ${GROUP} ]] && GROUP="--group ${GROUP}"

if ${DEBUG}; then
  set -x
  [[ -z ${DANTE_DEBUG:-''} ]] && export DANTE_DEBUG=1
fi
DANTE_DEBUG=${DANTE_DEBUG:-0}

##Functions
log() {
  echo "$(date +"%Y-%m-%d %T"): $*"
}

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
  CANDIDATE=$(curl -s https://nordvpn.com/fr/blog/nordvpn-linux-release-notes/ | grep -oP "NordVPN \K[0-9]\.[0-9]{1,2}" | head -1)
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
#setIPV6 ${NOIPV6}

setup_nordvpn() {
  nordvpn set technology ${TECHNOLOGY:-'NordLynx'}
  nordvpn set cybersec ${CYBER_SEC:-'off'}
  nordvpn set killswitch ${KILLERSWITCH:-'on'}
  nordvpn set ipv6 ${NOIPV6} 2>/dev/null
  [[ -n ${DNS:-''} ]] && nordvpn set dns ${DNS//[;,]/ }
  [[ -z ${DOCKER_NET:-''} ]] && DOCKER_NET="$(hostname -i | grep -Eom1 "^[0-9]{1,3}\.[0-9]{1,3}").0.0/12"
  nordvpn whitelist add subnet ${DOCKER_NET}
  [[ -n ${NETWORK:-''} ]] && for net in ${NETWORK//[;,]/ }; do nordvpn whitelist add subnet ${net}; done
  [[ -n ${PORTS:-''} ]] && for port in ${PORTS//[;,]/ }; do nordvpn whitelist add port ${port}; done
  [[ ${DEBUG} ]] && nordvpn -version && nordvpn settings
  localnet=$(hostname -i | grep -Eom1 "(^[0-9]{1,3}\.[0-9]{1,3})")
  nordvpn whitelist add subnet ${localnet}.0.0/16
}

#Main
checkLatest
#checkLatestApt
[[ -z ${CONNECT} ]] && exit 1
[[ ! -d ${RDIR} ]] && mkdir -p ${RDIR}

set_iptables DROP
setTimeZone
set_iptables ACCEPT

#start nordvpn daemon
while [ ! -S ${RDIR}/nordvpnd.sock ]; do
  log "WARNING: NORDVPN: restart nordvpn daemon as no socket was found"
  supervisorctl restart nordvpn
  sleep 4
done

#Use secrets if present
if [ -e /run/secrets/NORDVPN_LOGIN ]; then
  NORDVPN_LOGIN=$(cat /run/secrets/NORDVPN_LOGIN)
  NORDVPN_PASS=$(cat /run/secrets/NORDVPN_PASS)
fi

if [ -z ${NORDVPN_LOGIN} ] || [ -z ${NORDVPN_PASS} ]; then
  log "ERROR: NORDVPN: **********************"
  log "ERROR: NORDVPN: empty user or password"
  log "ERROR: NORDVPN: **********************"
  exit 1
fi

# login: already logged in return 1
res=$(nordvpn login --username ${NORDVPN_LOGIN} --password "${NORDVPN_PASS}" || true)
if [[ "${res}" != *"Welcome to NordVPN"*  ]] && [[ "${res}" != *"You are already logged in."* ]]; then
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
export INTERFACE=$(ifconfig | grep -oE "(tun|nordlynx)")
eval "echo \"$(cat /etc/danted.conf.tmpl)\"" >/etc/danted.conf

#check connected status
N=10
while [[ $(nordvpn status | grep -ic "connected") -eq 0 ]]; do
  sleep 10
  N--
  [[ ${n} -eq 0 ]] && log "ERROR: NORDVPN: cannot connect" && exit 1
done

supervisorctl start dante
