#!/usr/bin/env bash

set -euo pipefail
shopt -s nocasematch

#Vars
[[ -f /app/utils.sh ]] && source /app/utils.sh || true
if [[ ${DEBUG:-0} =~ (1|true|True|ON|On|on) ]]; then
  set -x
fi
TSEC=5
RDIR=/run/nordvpn/
ANALYTICS=${ANALYTICS:-off}
COUNTRY=${COUNTRY:-''}
CONNECT=${CONNECT:-''}
GROUP=${GROUP:-''}
NOIPV6=${NOIPV6:-'off'}
[[ -n ${COUNTRY} && -z ${CONNECT} ]] && CONNECT=${COUNTRY} && export CONNECT
CONNECT=${CONNECT// /_}
[[ "${GROUPID:-''}" =~ ^[0-9]+$ ]] && groupmod -g $GROUPID -o vpn
[[ -n ${GROUP} ]] && GROUP="--group ${GROUP}"


#Functions
setIPV6() {
  if [[ 0 -eq $(grep -c "net.ipv6.conf.all.disable_ipv6" /etc/sysctl.conf) ]]; then
    echo "net.ipv6.conf.all.disable_ipv6 = ${1}" >/etc/sysctl.conf
  else
    sed -i -E "s/net.ipv6.conf.all.disable_ipv6 = ./net.ipv6.conf.all.disable_ipv6 = ${1}/" /etc/sysctl.conf
  fi
  sysctl -p || true
}

#embedded in nordvpn client but not efficient in container. done in docker-compose
#setIPV6 ${NOIPV6}

#Main
[[ ! -d ${RDIR} ]] && mkdir -p ${RDIR}

isnordvpn6plus
#Overwrite docker dns as it may fail with specific configuration (dns on server)
chattr -i /etc/resolv.conf
echo "nameserver 1.1.1.1" >/etc/resolv.conf

setTimeZone

#stop killswitch that disable communication when no vpn is up
allow_traffic_before_vpn

# checkLatest commented as no more updated
checkLatestApt
if [[ -n ${NORDVPN_VERSION} ]]; then
  installedRequiredNordVpnClient
else
  log "INFO: NORDVPN: no required version specified, using installed version"
fi

#log all if required: IPTABLES_LOG=1
if [[ -f /app/logAll.sh ]]; then
  /app/logAll.sh
else
  log "INFO: logall feature not available
  "
fi

#make /dev/tun if missing
#[[ ${TECHNOLOGY} =~ nordlynx ]] && mkTun || true
mkTun

#if running stop it.
stop_transmission

#exit if required vars are missing
[[ -z ${CONNECT:-''} ]] && exit 1

UNP_IP=$(getCurrentWanIp)
# May be useful for Synology when iptables-nft has problems.
if [[ ${IPTABLES_LEGACY^^} != "N" ]]; then
   log "INFO: use iptable-legacy: https://developers.redhat.com/blog/2020/08/18/iptables-the-two-variants-and-their-relationship-with-nftables#"
   update-alternatives --set iptables /usr/sbin/iptables-legacy
fi
#Drop existing rules
set_iptables DROP
#Accept all.
set_iptables ACCEPT

if [[ -f /run/secrets/NORDVPN_PRIVKEY ]] && [[ ${TECHNOLOGY,,} == "nordlynx" ]]; then
  log "INFO: NORDLYNX: private key found, going for wireguard."
  getJsonFromNordApi
  if [[ ! -s /etc/resolv.conf ]]; then
    rm -f /etc/resolv.conf
    ln -s /run/resolvconf/resolv.conf /etc/resolv.conf
  fi
  generateWireguardConf
  connectWireguardVpn
  enforce_iptables
elif [[ ${NORDVPNCLIENT_INSTALLED} -eq 1 ]]; then
  log "Info: NORDLYNX: no wireguard private key found, connecting with nordvpn client."
  setup_nordvpn
  startNordVpn
  enforce_proxies_nordvpn
  [[ ${TECHNOLOGY,,} == "nordlynx" ]] && extractLynxConf || true
else
  log "Error: NORDLYNX: no nordvpn client, no wireguard private key, exiting."
  exit
fi

#
echo "waiting ${TSEC} for routing to be up"
sleep ${TSEC}

#connected
status=$(getVpnProtectionStatus)
currentIp=$(getCurrentWanIp)
log "INFO: current WAN IP: $(getCurrentWanIp) / unprotected ip: ${UNP_IP}, status: ${status}"
if [[ ${UNP_IP} == ${currentIp} ]]; then
  echo "Error, ${currentIp} is the same as host external ip (${UNP_IP}), exiting."
  exit 1
fi

if [[ ${status,,} != "connected" ]]; then
  echo "Warning, status is ${status} according to nordvpn."
fi

generateDantedConf
generateTinyproxyConf

log "INFO: DANTE: start proxy"
supervisorctl start dante

log "INFO: TINYPROXY: starting"
supervisorctl start tinyproxy

#supervisorctl start transmission

echo "back to start_vpn.sh"
