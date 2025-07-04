#!/usr/bin/env bash
#

DEBUG=${DEBUG:-0}
[[ "true" == ${DEBUG} ]] && export DEBUG=1 || true

#Define if not defined
TECHNOLOGY=${TECHNOLOGY:-'nordlynx'}
OBFUSCATE=${OBFUSCATE:-'off'}
PROTOCOL=${PROTOCOL:-'udp'}
GROUP=${GROUP:-'P2P'}
COUNTRY=${COUNTRY:-'argentina'}
CONNECT=${CONNECT:-''}
IPV6=${IPV6:-'off'}
GENERATE_WIREGUARD_CONF=${GENERATE_WIREGUARD_CONF:-"false"}
HTTP_PORT=8888
SOCK_PORT=1080

[[ -n ${COUNTRY} && -z ${CONNECT} ]] && export CONNECT=${COUNTRY}
[[ "${GROUPID:-''}" =~ ^[0-9]+$ ]] && groupmod -g $GROUPID -o vpn
[[ -n ${GROUP} ]] && GROUP="--group ${GROUP}"
#get container network (class B) to whitelist container subnet:  ${LOCALNET}.0.0/16
LOCALNET=$(hostname -i | grep -Eom1 "(^[0-9]{1,3}\.[0-9]{1,3})")
PROXY_HOST=$(ip -4 a show eth0 | grep -oP "(?<=inet )([^/]+)")

if [[ 1 -eq ${DEBUG:-0} ]]; then
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
    log "**********************************************************************"
  fi
}

checkLatestApt() {
  apt-get update
  VERSION=$(apt-cache policy nordvpn | grep -oP "Installed: \K.+")
  CANDIDATE=$(apt-cache policy nordvpn | grep -oP "Candidate: \K.+")
  CANDIDATE=${CANDIDATE:-${VERSION}}
  if [[ ${CANDIDATE} != "${VERSION}" ]] && [[ ${VERSION} != ${NORDVPN_VERSION} ]]; then
    log "**********************************************************************"
    log "WARNING: please update nordvpn from version ${VERSION} to ${CANDIDATE}"
    log "**********************************************************************"
  else
    log "INFO: checkLatestApt: No update needed for nordvpn, current version is ${VERSION}, latest is ${CANDIDATE}."
  fi
}

installedRequiredNordVpnClient() {
  MAXVER=$(apt-cache policy nordvpn | grep -oP "Candidat.*: \K.+")
  installed=$(apt-cache policy nordvpn | grep -oP "Install.*: \K.+")
  NEW=${1:-${NORDVPN_VERSION}}
  if [[ ${installed} != "${NEW}" ]]; then
    log "*************************************************************************************"
    log "INFO: current is ${installed}, installing nordvpn ${NEW}, latest version is ${MAXVER}"
    log "*************************************************************************************"
    log "INFO: stopping nordvpn's killswitch as 3.17.x have a bug preventing accessing to internet"
    [[ -n $(pgrep nordvpnd 2>&1) ]] && nordvpn s killswitch false || true
    apt-get update && apt-get install -y --allow-downgrades nordvpn=${NEW}
    installed=${NEW}
  fi
  if [[ ${installed} =~ 3.17.[0-9] ]]; then
    log "*************************************************************************************"
    log "Warning: 3.17.x versions are failing tests. (unable to connect). set NORDVPN_VERSION "
    log "Warning: to downgrade"
    log "*************************************************************************************"
  fi
}

getExtIp() {
  (ip -4 a show nordlynx 2>/dev/null || ip -4 a show nordtun 2>/dev/null) | grep -oP "(?<=inet )([^/]+)"
}

getEthIp() {
  ip -4 a show eth0 | grep -oP "(?<=inet )([^/]+)"
}

getEthCidr() {
  ip -j a show eth0 | jq -r '.[].addr_info[0]|"\( .broadcast // .local)/\(.prefixlen)"' | sed 's/255/0/g'
}

getTinyConf() {
  grep -v ^# /etc/tinyproxy/tinyproxy.conf | sed "/^$/d"
}

getDanteConf() {
  grep -v ^# /etc/sockd.conf | sed "/^$/d"
}

getTinyListen() {
  grep -oP "(?<=^Listen )[0-9\.]+" /etc/tinyproxy/tinyproxy.conf
}

changeTinyListenAddress() {
  listen_ip4=$(getTinyListen)
  current_ip4=$(getEthIp)
  if [[ ! -z ${listen_ip4} ]] && [[ ! -z ${current_ip4} ]] && [[ ${listen_ip4} != ${current_ip4} ]]; then
    #dante ecoute sur le nom de l'interface eth0
    echo "Tinyproxy: changing listening address from ${listen_ip4} to ${current_ip4}"
    sed -i "s/${listen_ip4}/${current_ip4}/" /etc/tinyproxy/tinyproxy.conf
    supervisorctl restart tinyproxy
  fi
}

createUserForAuthifNeeded(){
    TINYUSER=${1:-'NotAUser'}
    tinyid=$(id -u ${TINYUSER}) || true
    if [[ -z ${tinyid} ]]; then
      adduser -gecos "" --no-create-home --disabled-password --shell /sbin/nologin  --ingroup tinyproxy ${TINYUSER}
    fi
}

getTinyCred(){
  TCREDS_SECRET_FILE=/run/secrets/TINY_CREDS
  if [[ -f ${TCREDS_SECRET_FILE} ]]; then
    TINYUSER=$(sed -n '1p' ${TCREDS_SECRET_FILE})
    TINYPASS=$(sed -n '2p' -1 ${TCREDS_SECRET_FILE})
  fi
  if [[ -n ${TINYUSER:-''} ]] && [[ -n ${TINYPASS:-''} ]]; then
    TINYCRED="${TINYUSER}:${TINYPASS}@"
  else
    TINYCRED=""
  fi
  return ${TINYCRED}
}

## tests functions
testhproxy() {
  TCREDS=$(getTinyCred)
  IP=$(curl -m5 -sqx http://${TCREDS}${PROXY_HOST}:${HTTP_PORT} "https://ifconfig.me/ip")
  if [[ $? -eq 0 ]]; then
    echo "IP is ${IP}"
  else
    echo "curl through http proxy to https://ifconfig.me/ip failed"
    ((FAILED += 1))
  fi
}

testsproxy() {
  TCREDS=$(getTinyCred)
  IP=$(curl -m5 -sqx socks5://${TCREDS}${PROXY_HOST}:${SOCK_PORT} "https://ifconfig.me/ip")
  if [[ $? -eq 0 ]]; then
    echo "IP is ${IP}"
  else
    echo "curl through socks proxy to https://ifconfig.me/ip failed"
    ((FAILED += 1))
  fi
}
