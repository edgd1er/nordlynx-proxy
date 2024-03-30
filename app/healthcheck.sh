#!/usr/bin/env bash

set -e -u -o pipefail

N=3

##Functions
source /app/utils.sh

log() {
  echo "$(date +"%Y-%m-%d %T"): $*"
}

#check if eth0 ip has changed, change tinyproxy listen address if needed.
changeTinyListenAddress

#  status connected.
status=$(nordvpn status | grep -oP "Status: \K\w+")
if [ "connected" == ${status,,} ]; then
  exit 0
fi

# try N times to connect.
while ${N} -gt 0; do
  nordvpn connect ${CONNECT}
  sleep 10
  status=$(nordvpn status | grep -oP "Status: \K\w+")
  [[ "connected" == ${status,,} ]] && exit 0
  N--
done

log "ERROR: all ${N} reconnection tries failed, exiting."

exit 1
