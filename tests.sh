#!/usr/bin/env bash

set -euop pipefail

#vars
CPSE=compose.yml

#HTTP_PORT=28$(grep -oP '(?<=\- "28)[^:]+' ${CPSE})
#SOCK_PORT=20$(grep -oP '(?<=\- "20)[^:]+' ${CPSE})
HTTP_PORT=$(grep -oP "[0-9]{4}(?=:[0-9]{4}\" #http)" ${CPSE})
SOCK_PORT=$(grep -oP "[0-9]{4}(?=:[0-9]{4}\" #socks)" ${CPSE})
SERVICE=$(sed -n '/services:/{n;p}' ${CPSE} | grep -oP '\w+')
TRANS_PORT=9091
#Common
FAILED=0
INTERVAL=4
BUILD=0
if [[ ${SERVICE} == 'transmission' ]]; then
  TINYLOG=/config/log/tinyproxy/tinyproxy.log
  DANTELOG=/config/log/dante.log
else
  TINYLOG=/var/log/tinyproxy/tinyproxy.log
  DANTELOG=/var/log/dante.log
fi

PROXY_HOST=$(ip -4 -j -f inet a | jq -r 'first(.[]|select(.ifname | IN("enp1s0","eth0","wlp2s0","bond0"))| .addr_info[]|select(.family=="inet")|.local)')

#Functions
buildAndWait() {
  echo "Stopping and removing running containers"
  docker compose -f ${CPSE} down -v
  [[ ${BUILD} -eq 1 ]] && bb="--build" || bb=""
  echo "Building and starting image"
  docker compose -f ${CPSE} up -d ${bb}
  docker compose -f ${CPSE} exec lynx rm /var/log/{tinyproxy,dante}.log 2>/dev/null || true
  echo "Waiting for the container to be up.(every ${INTERVAL} sec)"
  logs=""
  while [ 0 -eq $(echo $logs | grep -c "exited: start_vpn (exit status 0; expected") ]; do
    logs="$(docker compose -f ${CPSE} logs)"
    sleep ${INTERVAL}
    ((n++))
    echo "loop: ${n}: $(docker compose -f ${CPSE} logs | tail -1)"
    [[ ${n} -eq 15 ]] && break || true
  done
  docker compose -f ${CPSE} logs
}

areProxiesPortOpened() {
  [[ ${SERVICE} == "transmission" ]] && TM="${TRANS_PORT}" || TM=""
  for PORT in ${HTTP_PORT} ${SOCK_PORT} ${TM}; do
    msg="Test connection to port ${PORT}: "
    if [ 0 -eq $(echo "" | nc -v -q1 -w2 ${PROXY_HOST} ${PORT} 2>&1|grep -c -P "(succeeded|open)") ]; then
      msg+=" Failed"
      ((FAILED += 1))
    else
      msg+=" OK"
    fi
    echo -e "$msg"
  done
}

testProxies() {
  FAILED=0
  if [[ -n $(which nc) ]]; then
    areProxiesPortOpened
  fi
  if [[ -f ./tiny_creds ]]; then
    usertiny=$(sed -n '1p' ./tiny_creds)
    passtiny=$(sed -n '2p' ./tiny_creds)
    echo "Getting tinyCreds from file: ${usertiny}:${passtiny}"
    TCREDS="${usertiny}:${passtiny}@"
    DCREDS="${TCREDS}"
  else
    usertiny=$(grep -oP "(?<=- TINYUSER=)[^ ]+" ${CPSE})
    passtiny=$(grep -oP "(?<=- TINYPASS=)[^ ]+" ${CPSE})
    echo "Getting tinyCreds from compose: ${usertiny}:${passtiny}"
    TCREDS="${usertiny}:${passtiny}@"
    DCREDS="${TCREDS}"
  fi
  if [[ -z ${usertiny:-''} ]]; then
    echo "No tinyCreds"
    TCREDS=""
    DCREDS=""
  fi
  declare -i try
  try=0
  vpnIP=
  while [[ -z $vpnIP ]] && [[ try -lt 3 ]]; do
    vpnIP=$(curl -4m5 -sx http://${TCREDS}${PROXY_HOST}:${HTTP_PORT} "https://ifconfig.me/ip")
    try+=1
  done
  if [[ $? -eq 0 ]] && [[ ${myIp} != "${vpnIP}" ]] && [[ ${#vpnIP} -gt 0 ]]; then
    echo "http proxy: IP is ${vpnIP}, mine is ${myIp}"
  else
    echo "Error, curl through http proxy to https://ifconfig.me/ip failed"
    echo "or IP (${myIp}) == vpnIP (${vpnIP})"
    ((FAILED += 1))
  fi

  #check detected ips
  try=0
  vpnIP=
  while [[ -z $vpnIP ]] && [[ try -lt 3 ]]; do
    vpnIP=$(curl -4m5 -sx socks5h://${DCREDS}${PROXY_HOST}:${SOCK_PORT} "https://ifconfig.me/ip") || true
    try+=1
  done
  if [[ $? -eq 0 ]] && [[ ${myIp} != "${vpnIP}" ]] && [[ ${#vpnIP} -gt 0 ]]; then
    echo "socks proxy: IP is ${vpnIP}, mine is ${myIp}"
  else
    #echo "Error, curl through socks proxy to https://ifconfig.me/ip failed"
    echo "Error, curl through socks proxy to http://ipv4.lafibre.info/ip.php failed"
    echo "or IP (${myIp}) == vpnIP (${vpnIP})"
    ((FAILED += 1))
  fi

  echo "# failed tests: ${FAILED}"
  return ${FAILED}
}

getInterfacesInfo() {
  docker compose exec ${SERVICE} bash -c "nordvpn version"
  docker compose exec ${SERVICE} bash -c "ip -j a |jq  '.[]|select(.ifname|test(\"wg0|tun|nordlynx\"))|.ifname'"
  itf=$(docker compose -f ${CPSE} exec ${SERVICE} ip -j a)
  echo eth0:$(echo $itf | jq -r '.[] |select(.ifname=="eth0")| .addr_info[].local')
  echo wg0: $(echo $itf | jq -r '.[] |select(.ifname=="wg0")| .addr_info[].local')
  echo nordlynx: $(echo $itf | jq -r '.[] |select(.ifname=="nordlynx")| .addr_info[].local')
  docker compose -f ${CPSE} exec ${SERVICE} bash -c 'echo "nordlynx conf: $(wg showconf nordlynx 2>/dev/null)"'
  docker compose -f ${CPSE} exec ${SERVICE} bash -c 'echo "wg conf: $(wg showconf wg0 2>/dev/null)"'
}

getAliasesOutput() {
  docker compose -f ${CPSE} exec ${SERVICE} bash -c 'while read -r line; do echo $line;eval $line;done <<<$(grep ^alias ~/.bashrc | cut -f 2 -d"'"'"'")'
}

getTransWebPage() {
  transcreds=""
  if [[ -e rpc_creds ]]; then
    transcreds="$(sed -n '1p' ./rpc_creds):$(sed -n '2p' ./rpc_creds)@"
  fi
  curl http://${transcreds}${PROXY_HOST}:${TRANS_PORT}/transmission/web/
}

checkOuput() {
  TINY_OUT=$(grep -oP '(?<=\- TINYLOGOUTPUT=)[^ ]+' ${CPSE}) || TINY_OUT="stdout"
  DANTE_OUT=$(grep -oP '(?<=\- DANTE_LOGOUTPUT=)[^ ]+' ${CPSE}) || DANTE_OUT="stdout"
  DANTE_RES=$(docker compose -f ${CPSE} exec ${SERVICE} grep -oP "(?<=^logoutput: ).+" /etc/danted.conf 2>/dev/null || true)
  DANTE_RES=${DANTE_RES:-'stdout'}
  TINY_RES=$(docker compose -f ${CPSE} exec ${SERVICE} grep -oP "(?<=^LogFile )(?:\")[^\"]+" /etc/tinyproxy/tinyproxy.conf | tr -d '"' || true)
  TINY_RES=${TINY_RES:-'stdout'}
  echo "Res tiny: ${TINY_RES}, dante: ${DANTE_RES}"
  echo -e "\nOut tiny: ${TINY_OUT}, dante: ${DANTE_OUT}"
  echo "Logs tiny: ${TINYLOG}, dante: ${DANTELOG}"
  #dantelog check
  echo "Logs output checks:"
  if [[ ${DANTE_OUT} =~ file ]]; then

    d=$(($(date +%s) - $(docker compose exec ${SERVICE} date +%s -r ${DANTELOG})))
    if [[ ${DANTE_RES} == stdout ]] || [[ 10000 -lt ${d} ]]; then
      echo "ERROR, $DANTELOG not found when $DANTE_OUT == file. Last access: ${d}, config found: ${DANTE_RES}"
    else
      echo "OK, $DANTELOG found as expected. Last access: ${d}"
    fi
  else
    #dante config stdout expected
    if [[ ${DANTE_RES} != "stdout" ]]; then
      echo "ERROR, $DANTE_OUT is stdout found when $DANTE_RES != stdout. config found: ${DANTE_RES}"
    else
      echo "OK, $DANTELOG not found as expected. DANTE config: ${DANTE_RES}"
    fi
  fi
  #tinyproxylog check
  if [[ ${TINY_OUT} =~ file ]]; then
    t=$(($(date +%s) - $(docker compose -f ${CPSE} exec ${SERVICE} date +%s -r ${TINYLOG})))
    if [[ ${TINY_RES} == stdout ]] || [[ 10000 -lt ${t} ]]; then
      echo "ERROR, $TINYLOG not found when $TINY_OUT == file. Last access: ${t}, config found: ${TINY_RES}"
    else
      echo "OK, $TINYLOG found as expected. Last access: ${t}."
    fi
  else
    ## TINY_RES should be = "no log"
    if [[ "stdout" != ${TINY_RES} ]]; then
      echo "ERROR, no log expected. log output(TINY_OUT)=$TINY_OUT, config(TINY_RES)=${TINY_RES}, TINYLOG=${TINYLOG}."
    else
      echo "OK, log output(TINY_OUT)=${TINY_OUT}, config(TINY_RES)=${TINY_RES}, TINYLOG=${TINYLOG}."
    fi
  fi
}

checkContainer() {
  if [[ "localhost" == "${PROXY_HOST}" ]] && [[ 1 -eq ${BUILD} ]]; then
    buildAndWait
  fi
  echo "***************************************************"
  echo "Testing container"
  echo "***************************************************"
  # check returned IP through http and socks proxy
  testProxies
  getInterfacesInfo
  getAliasesOutput
  if [[ ${SERVICE} == "transmission" ]]; then
    echo "Getting transmission web page"
    getTransWebPage
  fi
  checkOuput
  [[ 1 -eq ${BUILD} ]] && docker compose down
}

usage() {
  echo "$0: build and test container"
  echo -e "\t-b\tBuild and test"
  echo -e "\t-h\tThis help"
  echo -e "\t-t\tTest a running container"
  echo -e "\t-u\tTest an ubuntu container (debug nordvpn client)"
  echo -e "\t-v\tmode verbose"
  echo -e "\n\n username password may be saved to tiny_creds for proxy(http/socks), to nordvpn_creds for nordvpn client."
}

#Main
[[ -z $(which nc) ]] && echo "No nc found" && exit || true
[[ -e /.dockerenv ]] && PROXY_HOST=
myIp=$(curl -4m5 -sq https://ifconfig.me/ip)

# Get the options
while getopts ":bhtuv" option; do
  case ${option} in
  b)
    BUILD=1
    buildAndWait
    checkContainer
    ;;
  h) # display Help
    usage
    exit
    ;;
  t) # test a running container
    BUILD=0
    checkContainer
    ;;
  u) # build ubuntu image with nordvpn client
    ubuntuBuild
    exit
    ;;
  v)
    set -x
    ;;
  ? | *)
    echo "Unknown option"
    usage
    exit
    ;;
  esac
done

if [ $# -eq 0 ]; then
  usage
fi
