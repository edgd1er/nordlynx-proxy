#!/usr/bin/env bash

set -e -u -o pipefail

N=3

##Functions
log() {
  echo "$(date +"%Y-%m-%d %T"): $*"
}

#if protected
if test "$( curl -m 10 -s https://api.nordvpn.com/vpn/check/full | jq -r '.["status"]' )" = "Protected" ; then
  exit 0;
fi

status=$(nordvpn status | grep -oP "Status: \K\w+" )
# or connected (api might be offline), all is ok.
if [ "connected" == ${status,,} ]; then
    exit 0
fi


# try N times to connect.
while ${N} -ge 0
do
  nordvpn connect ${CONNECT}
  sleep 10
  status=$(nordvpn status | grep -oP "Status: \K\w+" )
  [[ "connected" == ${status,,} ]] && exit 0
  N--
done

log "ERROR: all ${n} reconnection tries failed, exiting."

exit 1