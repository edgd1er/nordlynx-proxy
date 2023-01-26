#!/usr/bin/env bash
set -euop pipefail

#var
PROXY_HOST="localhost"
HTTP_PORT=9888
SOCK_PORT=2081
FAILED=0
INTERVAL=4
BUILD=0
CONTAINER=lynx

#Function
runandWait() {
  echo "Stopping and removing running containers"
  docker compose down -v
  echo "Starting image"
  docker compose -f docker-compose.yml up -d
  echo "Waiting for the container to be up.(every ${INTERVAL} sec)"
  logs=""
  while [ 0 -eq $(echo $logs | grep -c "tinyproxy: started") ]; do
    logs="$(docker compose logs)"
    sleep ${INTERVAL}
    ((n++))
    echo "loop: ${n}"
    [[ ${n} -eq 15 ]] && break || true
  done
  docker compose logs
}

#Main
buildAndWait() {
  echo "Stopping and removing running containers"
  docker compose down -v
  echo "Building and starting image"
  docker compose -f docker-compose.yml up -d --build
  echo "Waiting for the container to be up.(every ${INTERVAL} sec)"
  logs=""
  n=0
  #  while [ 0 -eq $(echo $logs | grep -c "Initialization Sequence Completed") ]; do
  while [ 0 -eq $(echo $logs | grep -c "exited: start_vpn (exit status 0; expected") ]; do
    logs="$(docker compose logs)"
    sleep ${INTERVAL}
    ((n += 1))
    echo "loop: ${n}: $(docker compose logs | tail -1)"
    [[ ${n} -eq 15 ]] && break || true
  done
  docker compose logs
}

areProxiesPortOpened() {
  for PORT in ${HTTP_PORT} ${SOCK_PORT}; do
    msg="Test connection to port ${PORT}: "
    if [ 0 -eq $(echo "" | nc -v -q 2 ${PROXY_HOST} ${PORT} 2>&1 | grep -c "] succeeded") ]; then
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
  vpnIP=$(curl -m5 -sx http://${PROXY_HOST}:${HTTP_PORT} "https://ifconfig.me/ip")
  if [[ $? -eq 0 ]] && [[ ${myIp} != "${vpnIP}" ]] && [[ ${#vpnIP} -gt 0 ]]; then
    echo "http proxy: IP is ${vpnIP}, mine is ${myIp}"
  else
    echo "Error, curl through http proxy to https://ifconfig.me/ip failed"
    echo "or IP (${myIp}) == vpnIP (${vpnIP})"
    ((FAILED += 1))
  fi

  #check detected ips
  vpnIP=$(curl -m5 -sx socks5://${PROXY_HOST}:${SOCK_PORT} "https://ifconfig.me/ip")
  if [[ $? -eq 0 ]] && [[ ${myIp} != "${vpnIP}" ]] && [[ ${#vpnIP} -gt 0 ]]; then
    echo "socks proxy: IP is ${vpnIP}, mine is ${myIp}"
  else
    echo "Error, curl through socks proxy to https://ifconfig.me/ip failed"
    echo "or IP (${myIp}) == vpnIP (${vpnIP})"
    ((FAILED += 1))
  fi

  echo "# failed tests: ${FAILED}"
  return ${FAILED}
}

getInterfacesInfo() {
  docker compose exec ${CONTAINER} bash -c "ip -j a |jq  '.[]|select(.ifname|test(\"wg0|tun|nordlynx\"))|.ifname'"
  docker compose exec ${CONTAINER} echo -e "eth0: $(ip -j a | jq -r '.[] |select(.ifname=="eth0")| .addr_info[].local')\n wg0: $(ip -j a | jq -r '.[] |select(.ifname=="wg0")| .addr_info[].local')\nnordlynx: $(ip -j a | jq -r '.[] |select(.ifname=="nordlynx")| .addr_info[].local')"
  docker compose exec ${CONTAINER} bash -c 'echo "nordlynx conf: $(wg showconf nordlynx 2>/dev/null)"'
  docker compose exec ${CONTAINER} bash -c 'echo "wg conf: $(wg showconf wg0 2>/dev/null)"'
}

checkCountry() {
  if [[ 0 -eq $(docker compose logs |grep -ic "country: germany") ]]; then
    echo "Error, not connected to Germany"
  else
    echo "Connected to Germany"
  fi
}

#Main
[[ -e /.dockerenv ]] && PROXY_HOST=

#Check ports
[[ ${1:-''} == "-t" ]] && BUILD=0 || BUILD=1
myIp=$(curl -m5 -sq https://ifconfig.me/ip)

if [[ "localhost" == "${PROXY_HOST}" ]] && [[ 1 -eq ${BUILD} ]]; then
  buildAndWait
  echo "***************************************************"
  echo "Testing container"
  echo "***************************************************"
  # check returned IP through http and socks proxy
  testProxies
  getInterfacesInfo
  checkCountry
  [[ 1 -eq ${BUILD} ]] && docker compose down
else
  echo "***************************************************"
  echo "Testing container"
  echo "***************************************************"
  # check returned IP through http and socks proxy
  testProxies
  checkCountry
fi
