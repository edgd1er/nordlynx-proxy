#!/bin/bash

set -u -o pipefail

##Functions
source /app/utils.sh
RDIR=/run/nordvpn

set_iptables() {
  action=${1:-'DROP'}
  log "INFO: setting iptables policy to ${action}"
  iptables -F
  iptables -X
  iptables -P INPUT ${action}
  iptables -P FORWARD ${action}
  iptables -P OUTPUT ${action}
}

enforce_proxies_iptables() {
  log "proxies: allow ports 1080, ${TINYPORT}"
  nordvpn whitelist add port 1080 protocol TCP
  nordvpn whitelist add port 1080 protocol UDP
  nordvpn whitelist add port ${TINYPORT} protocol TCP
  iptables -L
}

setIPV6() {
  if [[ 0 -eq $(grep -c "net.ipv6.conf.all.disable_ipv6" /etc/sysctl.conf) ]]; then
    echo "net.ipv6.conf.all.disable_ipv6 = ${1}" >/etc/sysctl.conf
  else
    sed -i -E "s/net.ipv6.conf.all.disable_ipv6 = ./net.ipv6.conf.all.disable_ipv6 = ${1}/" /etc/sysctl.conf
  fi
  sysctl -p || true
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
  [[ ${DEBUG} ]] && nordvpn version && nordvpn settings
  nordvpn whitelist add subnet ${LOCALNET}.0.0/16
  if [[ -n ${LOCAL_NETWORK:-''} ]]; then
    eval $(/sbin/ip route list match 0.0.0.0 | awk '{if($5!="tun0"){print "GW="$3"\nINT="$5; exit}}')
    log "LOCAL_NETWORK: ${LOCAL_NETWORK}, Gateway: ${GW}, device ${INT}"
    if [[ -n ${GW:-""} ]] && [[ -n ${INT:-""} ]]; then
      for localNet in ${LOCAL_NETWORK//,/ }; do
        log "INFO: NORDVPN: whitelisting network ${localNet}"
        nordvpn whitelist add subnet ${localNet}
        log "INFO: NORDVPN: adding route to local network ${localNet} via ${GW} dev ${INT}"
        /sbin/ip route add "${localNet}" via "${GW}" dev "${INT}"
      done
    fi
  else
    log "WARNING: OVPN: undefined LOCAL_NETWORK, sockd and http proxies available only through 127.0.0.1 or 0.0.0.0"
  fi
}

mkTun() {
  # Create a tun device see: https://www.kernel.org/doc/Documentation/networking/tuntap.txt
  if [ ! -c /dev/net/tun ]; then
    log "INFO: OVPN: Creating tun interface /dev/net/tun"
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200
    chmod 600 /dev/net/tun
  fi
}

extractLynxConf() {
  [[ ${GENERATE_WIREGUARD_CONF} != true ]] && return || true
  if [[ ${TECHNOLOGY,,} != nordlynx ]]; then
    log "Info: NORDPVN: Connection is not a Nordlynx (wireguard) type. Cannot extract wireguard information"
    return
  fi
  if [[ -z $(command -v wg) ]]; then
    log "Error: NORDPVN: wireguard kernel and tools not installed. installing required packages, using additionnal 317 MB of disk space."
    apt-get update && apt-get install -y --no-install-recommends wireguard wireguard-tools
  fi
  wg showconf nordlynx >/etc/wireguard/wg0.conf
  chmod 600 /etc/wireguard/wg0.conf
  log "Wireguard configuration written to /etc/wireguard/wg0.conf"
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
[[ -z ${CONNECT:-''} ]] && exit 1
[[ ! -d ${RDIR} ]] && mkdir -p ${RDIR}

log "INFO: NORDVPN: starting nordvpn daemon"
action=start
isRunning=$(supervisorctl status nordvpnd | grep -c RUNNING) || true
[[ 0 -le ${isRunning} ]] && action=restart
[[ -e ${RDIR}/nordvpnd.sock ]] && rm -f ${RDIR}/nordvpnd.sock
supervisorctl ${action} nordvpnd
sleep 4
#start nordvpn daemon
while [ ! -S ${RDIR}/nordvpnd.sock ]; do
  log "WARNING: NORDVPN: restart nordvpn daemon as no socket was found"
  supervisorctl restart nordvpnd
  sleep 4
done

#make /dev/tun if missing
#[[ ${TECHNOLOGY} =~ nordlynx ]] && mkTun || true
mkTun
enforce_proxies_iptables


#Use env login if present
if [[ -z ${NORDVPN_PASS:-''} ]] && [[ -n ${NORDVPN_LOGIN:-''} ]]; then
	log "WARNING: No password env value found, assuming token."
	logincmd="login --token ${NORDVPN_LOGIN:-''}"
else
	logincmd="login --username ${NORDVPN_LOGIN:-''} --password ${NORDVPN_PASS:-''}"
fi

#Use secrets if present
if [ -e /run/secrets/NORDVPN_CREDS ]; then
  mapfile -t -n 2 vars </run/secrets/NORDVPN_CREDS
  if [[ ${#vars[*]} -eq 2 ]]; then
    NORDVPN_LOGIN=${vars[0]}
    NORDVPN_PASS=${vars[1]}
    logincmd="login --username ${vars[0]} --password ${vars[1]}"
  elif [[ ${#vars[*]} -eq 1 ]]; then
    log "WARNING: Only one line found, assuming token."
    NORDVPN_LOGIN=${vars[0]}
    NORDVPN_PASS=''
    logincmd="login --token ${vars[0]}"
  fi
fi

if [ -z ${NORDVPN_LOGIN:-''} ] || [ -z "${logincmd}" ]; then
  log "ERROR: NORDVPN: **********************"
  log "ERROR: NORDVPN: empty user or token   "
  log "ERROR: NORDVPN: **********************"
  exit 1
fi

# login: already logged in return 1
res="$(nordvpn ${logincmd})" || true
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
status=$(nordvpn status)
server=$(echo -e "${status}" | grep -oP "(?<=server: ).+")
serverIp=$(echo -e "${status}" | grep -oP "(?<=IP: ).+")
extractLynxConf

#check if installed nordvpn app is the latest available
# checkLatest
#[[ 1 -eq $? ]] && checkLatestApt
checkLatestApt

echo -e "${status}"
curip=$(curl -s 'https://api.ipify.org?format=json' | jq .ip)
log "INFO: detected WAN IP: ${curip} / nordvpn status: ${serverIp} = ${server}"

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
