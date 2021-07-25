#!/bin/bash

set -eu

RDIR=/run/nordvpn
DEBUG=${DEBUG:-false}
COUNTRY=${COUNTRY:-''}
NOIPV6=${NOIPV6:-'off'}

if ${DEBUG}; then
  set -x
  [[ -z ${DANTE_DEBUG:-''} ]] && export DANTE_DEBUG=1
fi

DANTE_DEBUG=${DANTE_DEBUG:-0}

#  sed -i -E "s/debug: [^$]+/debug: 2/" /etc/danted.conf

[[ -n ${COUNTRY} && -z ${CONNECT} ]] && CONNECT=${COUNTRY}
[[ "${GROUPID:-''}" =~ ^[0-9]+$ ]] && groupmod -g $GROUPID -o vpn

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

#embedded in nordvpn client
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
  [[ -n ${DEBUG} ]] && nordvpn -version && nordvpn settings
  localnet=$(hostname -i | grep -Eom1 "(^[0-9]{1,3}\.[0-9]{1,3})")
  nordvpn whitelist add subnet ${localnet}.0.0/16
}

#Main
set_iptables DROP
[[ ! -d ${RDIR} ]] && mkdir -p ${RDIR}
setTimeZone

set_iptables ACCEPT
#start nordvpn daemon
supervisorctl start nordvpnd

while [ ! -S ${RDIR}/nordvpnd.sock ]; do
  sleep 0.25
done

nordvpn login --username ${USER} --password "${PASS}"
setup_nordvpn
nordvpn connect ${CONNECT} || exit 1
nordvpn status

log "INFO: current WAN IP: $(curl -s 'https://api.ipify.org?format=json' | jq .ip)"

log "INFO: DANTE: configuration"
export INTERFACE=$(ifconfig | grep -oE "(tun|nordlynx)")
eval "echo \"$(cat /etc/danted.conf.tmpl)\"" >/etc/danted.conf

#checkp connected status
while [[ $(nordvpn status | grep -ic "connected") -eq 0 ]]; do
  sleep 10
done

supervisorctl start dante
