#!/usr/bin/env bash

set -euop pipefail

#var
PROXY_HOST="localhost"
#PROXY_HOST="omv.mission.lan"
#PROXY_HOST="holdom3.mission.lan"
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
  echo "Building and starting image"
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
  if [[ -f ./tiny_creds ]]; then
    usertiny=$(head -1 ./tiny_creds)
    passtiny=$(tail -1 ./tiny_creds)
    echo "Getting tinyCreds from file: ${usertiny}:${passtiny}"
    TCREDS="${usertiny}:${passtiny}@"
    DCREDS="danteuser:${passtiny}@"
  else
    usertiny=$(grep -oP "(?<=- TINYUSER=)[^ ]+" docker-compose.yml)
    passtiny=$(grep -oP "(?<=- TINYPASS=)[^ ]+" docker-compose.yml)
    echo "Getting tinyCreds from compose: ${usertiny}:${passtiny}"
    TCREDS="${usertiny}:${passtiny}@"
    DCREDS="danteuser:${passtiny}@"
  fi
  if [[ -z ${usertiny:-''} ]]; then
    echo "No tinyCreds"
    TCREDS=""
    DCREDS=""
  fi
  vpnIP=$(curl -m5 -sx http://${TCREDS}${PROXY_HOST}:${HTTP_PORT} "https://ifconfig.me/ip") || true
  if [[ $? -eq 0 ]] && [[ ${myIp} != "${vpnIP}" ]] && [[ ${#vpnIP} -gt 0 ]]; then
    echo "http proxy: IP is ${vpnIP}, mine is ${myIp}"
  else
    echo "Error, curl through http proxy to https://ifconfig.me/ip failed"
    echo "or IP (${myIp}) == vpnIP (${vpnIP})"
    ((FAILED += 1))
  fi

  #check detected ips
  vpnIP=$(curl -m5 -sx socks5h://${DCREDS}${PROXY_HOST}:${SOCK_PORT} "https://ifconfig.me/ip") || true
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
  docker compose exec ${CONTAINER} bash -c "nordvpn version"
  docker compose exec ${CONTAINER} bash -c "ip -j a |jq  '.[]|select(.ifname|test(\"wg0|tun|nordlynx\"))|.ifname'"
  docker compose exec ${CONTAINER} echo -e "eth0: $(ip -j a | jq -r '.[] |select(.ifname=="eth0")| .addr_info[].local')\n wg0: $(ip -j a | jq -r '.[] |select(.ifname=="wg0")| .addr_info[].local')\nnordlynx: $(ip -j a | jq -r '.[] |select(.ifname=="nordlynx")| .addr_info[].local')"
  docker compose exec ${CONTAINER} bash -c 'echo "nordlynx conf: $(wg showconf nordlynx 2>/dev/null)"'
  docker compose exec ${CONTAINER} bash -c 'echo "wg conf: $(wg showconf wg0 2>/dev/null)"'
}

checkContainer() {
  if [[ "localhost" == "${PROXY_HOST}" ]] && [[ 1 -eq ${BUILD} ]]; then
    buildAndWait
    echo "***************************************************"
    echo "Testing container"
    echo "***************************************************"
    # check returned IP through http and socks proxy
    testProxies
    getInterfacesInfo
    [[ 1 -eq ${BUILD} ]] && docker compose down
  else
    echo "***************************************************"
    echo "Testing container"
    echo "***************************************************"
    # check returned IP through http and socks proxy
    testProxies
    getInterfacesInfo
  fi
}

ubuntuBuild() {
  docker buildx build -f Dockerfile.nrd --build-arg VERSION=3.17.4 -t nordvpnu .
  TKN=$(<nordvpn_creds)
  echo "nordvpn login -token ${TKN}"
  #docker run -it --rm nordvpnu "nordvpn login -token ${TKN}; bash"
  docker run --name nordvpnu --privileged --rm nordvpnu
  docker exec -t nordvpnu "nordvpn login -token ${TKN}; nordvpn c -group p2p germany berlin;"
}

usage() {
  echo "$0: build and test container"
  echo -e "\t-b\tBuild and test"
  echo -e "\t-t\tTest a running container"
  echo -e "\t-u\tTest an ubuntu container (debug nordvpn client)"
  echo -e "\t-h\tThis help"
}

#Main
[[ -e /.dockerenv ]] && PROXY_HOST=
myIp=$(curl -4 -m5 -sq https://ifconfig.me/ip)

# Get the options
while getopts ":bhtu" option; do
  case ${option} in
  b)
    BUILD=1
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
