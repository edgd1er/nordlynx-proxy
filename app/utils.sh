#!/usr/bin/env bash
#

DEBUG=${DEBUG:-0}
[[ "true" == ${DEBUG} ]] && export DEBUG=1 || true

COUNTRY=${COUNTRY:-''}
CONNECT=${CONNECT:-''}
GROUP=${GROUP:-''}
IPV6=${IPV6:-'off'}
TECHNOLOGY=${TECHNOLOGY:-'nordlynx'}
[[ -n ${COUNTRY} && -z ${CONNECT} ]] && export CONNECT=${COUNTRY}
[[ "${GROUPID:-''}" =~ ^[0-9]+$ ]] && groupmod -g $GROUPID -o vpn
[[ -n ${GROUP} ]] && GROUP="--group ${GROUP}"
#get container network (class B) to whitelist container subnet:  ${LOCALNET}.0.0/16
LOCALNET=$(hostname -i | grep -Eom1 "(^[0-9]{1,3}\.[0-9]{1,3})")
GENERATE_WIREGUARD_CONF=${GENERATE_WIREGUARD_CONF:-"false"}

PROXY_HOST=$(ip -4 a show eth0 | grep -oP "(?<=inet )([^/]+)")
HTTP_PORT=8888
SOCK_PORT=1080

if [[ 1 -eq ${DEBUG} ]]; then
  set -x
  #set DANTE_DEBUG only if not already set
  [[ -z ${DANTE_DEBUG:-''} ]] && export DANTE_DEBUG=9
else
  #set DANTE_DEBUG onl if not already set
  DANTE_DEBUG=${DANTE_DEBUG:-0}
fi
[[ 1 -eq ${DEBUG} ]] && [[ 0 -eq ${DANTE_DEBUG} ]] && DANTE_DEBUG=" 9" && set -x

eval $(/sbin/ip route list match 0.0.0.0 | awk '{if($5!="tun0"){print "GW="$3"\nINT="$5; exit}}')

fatal_error() {
  #printf "${TIME_FORMAT} \e[41mERROR:\033[0m %b\n" "$*" >&2
  printf "\e[41mERROR:\033[0m %b\n" "$*" >&2
  exit 1
}

log() {
  echo "$(date +"%Y-%m-%d %T"): $*"
}

setTimeZone() {
  [[ ${TZ} == $(cat /etc/timezone) ]] && return
  log "INFO: Setting timezone to ${TZ}"
  ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime
  dpkg-reconfigure -fnoninteractive tzdata
}

checkLatest() {
  res=$(curl -LSs "https://nordvpn.com/en/blog/nordvpn-linux-release-notes/")
  [[ -z $res ]] && return 1
  CANDIDATE=$(echo ${res} | grep -oP "NordVPN \K[0-9]\.[0-9]{1,2}" | head -1)
  [[ -z ${CANDIDATE} ]] && return 1
  VERSION=$(dpkg-query --showformat='${Version}' --show nordvpn)
  if [[ ${VERSION} =~ ${CANDIDATE} ]]; then
    log "INFO: checkLatest: No update needed for nordvpn (${VERSION})"
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
  if [[ ${CANDIDATE} != "${VERSION}" ]]; then
    log "**********************************************************************"
    log "WARNING: please update nordvpn from version ${VERSION} to ${CANDIDATE}"
    log "WARNING: please update nordvpn from version ${VERSION} to ${CANDIDATE}"
    log "**********************************************************************"
  else
    log "INFO: checkLatestApt: No update needed for nordvpn (${VERSION})"
  fi
}

getExtIp() {
  ip -4 a show nordlynx | grep -oP "(?<=inet )([^/]+)"
}

getIntIp() {
  ip -4 a show eth0 | grep -oP "(?<=inet )([^/]+)"
}

getIntCidr() {
  ip -j a show eth0 | jq -r '.[].addr_info[0]|"\( .broadcast)/\(.prefixlen)"' | sed 's/255/0/g'
}

## tests functions
getTinyConf() {
  grep -v ^# /etc/tinyproxy/tinyproxy.conf | sed "/^$/d"
}

getDanteConf() {
  grep -v ^# /etc/sockd.conf | sed "/^$/d"
}

testhproxy() {
  IP=$(curl -m5 -sqx http://${PROXY_HOST}:${HTTP_PORT} "https://ifconfig.me/ip")
  if [[ $? -eq 0 ]]; then
    echo "IP is ${IP}"
  else
    echo "curl through http proxy to https://ifconfig.me/ip failed"
    ((FAILED += 1))
  fi
}

testsproxy() {
  IP=$(curl -m5 -sqx socks5://${PROXY_HOST}:${SOCK_PORT} "https://ifconfig.me/ip")
  if [[ $? -eq 0 ]]; then
    echo "IP is ${IP}"
  else
    echo "curl through socks proxy to https://ifconfig.me/ip failed"
    ((FAILED += 1))
  fi
}
