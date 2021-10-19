[![lint nordlynx proxy dockerfile](https://github.com/edgd1er/nordlynx-proxy/actions/workflows/lint.yml/badge.svg?branch=main)](https://github.com/edgd1er/nordvpn-proxy/actions/workflows/lint.yml)

[![build nordlynx proxy multi-arch images](https://github.com/edgd1er/nordlynx-proxy/actions/workflows/buildPush.yml/badge.svg?branch=main)](https://github.com/edgd1er/nordvpn-proxy/actions/workflows/buildPush.yml)

![Docker Size](https://badgen.net/docker/size/edgd1er/nordlynx-proxy?icon=docker&label=Size)
![Docker Pulls](https://badgen.net/docker/pulls/edgd1er/nordlynx-proxy?icon=docker&label=Pulls)
![Docker Stars](https://badgen.net/docker/stars/edgd1er/nordlynx-proxy?icon=docker&label=Stars)
![ImageLayers](https://badgen.net/docker/layers/edgd1er/nordlynx-proxy?icon=docker&label=Layers)

# nordlynx-proxy

This is a NordVPN docker container that connects the recommended NordVPN servers through nordvpn client, and starts a SOCKS5 proxy (dante).
Openvpn and nordlynx technology are available.

Added docker image version for raspberry.  

Whenever the connection is lost, nordvpn client has a killswitch to obliterate the connection.

## What is this?

This image is a variation of nordvpn-proxy. The latter is base on openvpn. 
The nordvpn application replace openvpn. Nordvpn version of [wireguard](https://nordvpn.com/blog/wireguard-simplicity-efficiency/) is [nordlynx](https://nordvpn.com/blog/nordlynx-protocol-wireguard/).

you can then expose port `1080` from the container to access the VPN connection via the SOCKS5 proxy.

To sum up, this container:
* Opens the best connection to NordVPN using nordvpn app NordVpn API results according to your criteria.
* Starts a SOCKS5 proxy that routes `eth0` to `tun0.nordlynx` with [dante-server](https://www.inet.no/dante/).
* nordvpn dns servers perform resolution, by default.
* uses supervisor to handle easily services.

The main advantages are:
- you get the best recommendation for each selection.
- can select openvpn or nordlynx protocol
- use of nordVpn app features (Killswitch, cybersec, ....)

## Usage

The container may use environment variable to select a server, otherwise the best recommended server is selected:
see environment variables to get all available options or [nordVpn support](https://support.nordvpn.com/Connectivity/Linux/1325531132/Installing-and-using-NordVPN-on-Debian-Ubuntu-Raspberry-Pi-Elementary-OS-and-Linux-Mint.htm#Settings).

adding 
``` docker
sysclts:
 - net.ipv6.conf.all.disable_ipv6=1 # disable ipv6
 ```
  might be needed, if nordvpn cannot change the settings itself.

* TECHNOLOGY=[NordLynx]/[OpenVPN], default: NordLynx
* CONNECT = [country]/[server]/[country_code]/[city] or [country] [city], if none provide you will connect to the recommended server.
* [COUNTRY](https://api.nordvpn.com/v1/servers/countries) define the exit country.
* [GROUP](https://api.nordvpn.com/v1/servers/groups): Africa_The_Middle_East_And_India, Asia_Pacific, Europe, Onion_Over_VPN, P2P, Standard_VPN_Servers, The_Americas, although many categories are possible, p2p seems more adapted.
* NORDVPN_USER=email (As of 21/07/25, Service credentials are not allowed.)
* NORDVPN_PASS=pass 
* CYBER_SEC, default off
* KILLERSWITCH, default on
* DNS: change dns
* PORTS: add ports to allow
* NETWORK: add subnet to allow
* DOCKER_NET: optional, docker CIDR extracted from container ip if not set. 

### Container variables
* DEBUG: (true/false) verbose mode for initial script lauch and dante server.

```bash
docker run -it --rm --cap-add NET_ADMIN -p 1081:1080 --device /dev/net/tun -e NORDVPN_USER=<email> -e NORDVPN_PASS='<pass>' -e COUNTRY=Poland
 -e edgd1er/nordlynx-proxy
```

```yaml
version: '3.8'
services:
  proxy:
    image: edgd1er/nordvpn-proxy:latest
    restart: unless-stopped
    ports:
      - "1080:1080"
    devices:
      - /dev/net/tun
    sysctls:
      - net.ipv6.conf.all.disable_ipv6=1 # disable ipv6
      #      - net.ipv4.conf.all.rp_filter=2 # Loose Reverse Path: https://access.redhat.com/solutions/53031
    cap_add:
      - NET_ADMIN               # Required
#      - SYS_MODULE              # Required for TECHNOLOGY=NordLynx
    environment:
      - TZ=America/Chicago
      - CONNECT=uk
      - TECHNOLOGY=NordLynx
      - DEBUG=
      - NORDVPN_USER=<email> #Not required if using secrets
      - NORDVPN_PASS=<pass> #Not required if using secrets
    secrets:
      - NORDVPN_LOGIN
      - NORDVPN_PASS

secrets:
    NORDVPN_LOGIN:
        file: ./nordvpn_login
    NORDVPN_PASS:
        file: ./nordvpn_pwd
```


