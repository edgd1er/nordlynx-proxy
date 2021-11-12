[![lint nordlynx proxy dockerfile](https://github.com/edgd1er/nordlynx-proxy/actions/workflows/lint.yml/badge.svg?branch=main)](https://github.com/edgd1er/nordvpn-proxy/actions/workflows/lint.yml)

[![build nordlynx proxy multi-arch images](https://github.com/edgd1er/nordlynx-proxy/actions/workflows/buildPush.yml/badge.svg?branch=main)](https://github.com/edgd1er/nordvpn-proxy/actions/workflows/buildPush.yml)

![Docker Size](https://badgen.net/docker/size/edgd1er/nordlynx-proxy?icon=docker&label=Size)
![Docker Pulls](https://badgen.net/docker/pulls/edgd1er/nordlynx-proxy?icon=docker&label=Pulls)
![Docker Stars](https://badgen.net/docker/stars/edgd1er/nordlynx-proxy?icon=docker&label=Stars)
![ImageLayers](https://badgen.net/docker/layers/edgd1er/nordlynx-proxy?icon=docker&label=Layers)

# nordlynx-proxy

Warning 1: login process is very unstable: 
```
It's not you, it's us. We're having trouble reaching our servers. If the issue persists, please contact our customer support.
```

Warning 2: soon this image wil be usable due to login/password process deprecation, replaced by nordaccount: 
```
Password login is deprecated.
'nordvpn login --nordaccount' will become the default login method in the future.
```

This is a NordVPN docker container that connects to the NordVPN recommended servers through nordvpn client, and starts both a SOCKS5 proxy (dante) and an http proxy.
Openvpn and nordlynx technology are available.

Added docker image version for raspberry.  

Whenever the connection is lost, nordvpn client has a killswitch to obliterate the connection.

current nordvpn application version: 3.12.0-1

## What is this?

This image is a variation of nordvpn-proxy. The latter is based on openvpn. 
The nordvpn application replace openvpn. Nordvpn version of [wireguard](https://nordvpn.com/blog/wireguard-simplicity-efficiency/) is [nordlynx](https://nordvpn.com/blog/nordlynx-protocol-wireguard/).

you can then expose port `1080` from the container to access the VPN connection via the SOCKS5 proxy, or use the `8888` http's proxy port.

To sum up, this container:
* Opens the best connection to NordVPN using nordvpn app NordVpn API results according to your criteria.
* Starts a HTTP proxy that route `eth0:8888` to `eth0:1080` (socks server) with [tinyproxy](https://tinyproxy.github.io/)
* Starts a SOCKS5 proxy that routes `eth0:1080` to `tun0/nordlynx` with [dante-server](https://www.inet.no/dante/).
* nordvpn dns servers perform resolution, by default.
* uses supervisor to handle easily services.

The main advantages are:
- you get the best recommendation for each combination of parameters (country, groups, protocol).
- can select openvpn or nordlynx protocol
- use of nordVpn app features (Killswitch, cybersec, ....)


please note, that to avoid dns problem when the dns service is on the same host, /etc/resolv.conf is set to google DNS (1.1.1.1).
That DNS is used only during startup (check latest nordvpn version), NordVpn dns are set when vpn is up.

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
* LOCAL_NETWORK: add subnet to allow, multiple values possible net1, net2, net3, ....
* DOCKER_NET: optional, docker CIDR extracted from container ip if not set. 

### docker-compose with env variables explained

```yaml
version: '3.8'
services:
  proxy:
    image: edgd1er/nordlynx-proxy:latest
    restart: unless-stopped
    ports:
      - "1080:1080"
      - "8888:8888"
    devices:
      - /dev/net/tun
    sysctls:
      - net.ipv6.conf.all.disable_ipv6=1 # disable ipv6
    cap_add:
      - NET_ADMIN               # Required
    environment:
      - TZ=America/Chicago
      - IPTABLES_LOG=1 #active packet logging
      - CONNECT= #Optionnal, override COUNTRY, specify country+serveur number like uk715
      - COUNTRY=de #Optional, by default, servers in user's coyntry.
      - GROUP=P2P #Africa_The_Middle_East_And_India, Asia_Pacific, Europe, Onion_Over_VPN, P2P, Standard_VPN_Servers, The_Americas
      - KILLERSWITCH=on #Optional, on by default, kill Switch is a feature helping you prevent unprotected access to the internet when your traffic doesn't go through a NordVPN server.
      - CYBER_SEC=off #CyberSec is a feature protecting you from ads, unsafe connections, and malicious sites
      - TECHNOLOGY=NordLynx #openvpn or nordlynx
      - IPV6=off #optional, off by default, on/off available, off disable IPV6 in nordvpn app
      - NORDVPN_USER=<email> #Not required if using secrets
      - NORDVPN_PASS=<pass> #Not required if using secrets
      - DEBUG=0 #(0/1) activate debug mode for scripts, dante, tinproxy
      - LOCAL_NETWORK=192.168.53.0/24 #LAN to route through proxies and vpn.
      - TINYLOGLEVEL=error #Optional, default error: Critical (least verbose), Error, Warning, Notice, Connect (to log connections without Info's noise), Info
      - TINYPORT=8888 #define tinyport inside the container, optional, 8888 by default,
      - DANTE_LOGLEVEL="error" #Optional, error by default, available values: connect disconnect error data
      - DANTE_ERRORLOG=/dev/stdout #Optional, /dev/null by default
      - DANTE_DEBUG=0 # Optional, 0-9
    secrets:
      - NORDVPN_LOGIN
      - NORDVPN_PASS

secrets:
    NORDVPN_LOGIN:
        file: ./nordvpn_login
    NORDVPN_PASS:
        file: ./nordvpn_pwd
```


