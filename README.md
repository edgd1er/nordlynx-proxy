[![lint nordlynx proxy dockerfile](https://github.com/edgd1er/nordlynx-proxy/actions/workflows/lint.yml/badge.svg?branch=main)](https://github.com/edgd1er/nordvpn-proxy/actions/workflows/lint.yml)

[![Debian based image ](https://github.com/edgd1er/nordlynx-proxy/actions/workflows/buildPush_debian.yml/badge.svg?branch=main)](https://github.com/edgd1er/nordlynx-proxy/actions/workflows/buildPush_debian.yml)

[![Debian based image ](https://github.com/edgd1er/nordlynx-proxy/actions/workflows/buildPush_ubuntu.yml/badge.svg?branch=main)](https://github.com/edgd1er/nordlynx-proxy/actions/workflows/buildPush_ubuntu.yml)

* Without wireguard tools:&emsp;&emsp;&emsp;&emsp;&emsp;&ensp;
  ![Docker Pulls](https://badgen.net/docker/pulls/edgd1er/nordlynx-proxy?icon=docker&label=Pulls)
  ![Docker Stars](https://badgen.net/docker/stars/edgd1er/nordlynx-proxy?icon=docker&label=Stars)
  * Debian bookworm &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;
    ![Docker Size](https://badgen.net/docker/size/edgd1er/nordlynx-proxy/latest-debian?icon=docker&label=Size)
    ![ImageLayers](https://badgen.net/docker/layers/edgd1er/nordlynx-proxy/latest-debian?icon=docker&label=Layers)
  * Ubuntu based image:&emsp;&emsp;&emsp;&emsp;&emsp;
     ![Docker Size](https://badgen.net/docker/size/edgd1er/nordlynx-proxy/latest-ubuntu/amd64?icon=docker&label=Size)
     ![ImageLayers](https://badgen.net/docker/layers/edgd1er/nordlynx-proxy/latest-ubuntu/amd64?icon=docker&label=Layers)
* With wireguard tools:&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;
  ![Docker Pulls](https://badgen.net/docker/pulls/edgd1er/nordlynx-proxy-wg?icon=docker&label=Pulls)
  ![Docker Stars](https://badgen.net/docker/stars/edgd1er/nordlynx-proxy-wg?icon=docker&label=Stars)
  * Debian bookworm based image &nbsp;
  ![Docker Size](https://badgen.net/docker/size/edgd1er/nordlynx-proxy-wg/latest-debian?icon=docker&label=Size)
  ![ImageLayers](https://badgen.net/docker/layers/edgd1er/nordlynx-proxy-wg/latest-debian?icon=docker&label=Layers)
  * Ubuntu 24.04 based image: &emsp;&emsp;
![Docker Size](https://badgen.net/docker/size/edgd1er/nordlynx-proxy-wg/latest-ubuntu?icon=docker&label=Size)
![ImageLayers](https://badgen.net/docker/layers/edgd1er/nordlynx-proxy-wg/latest-ubuntu?icon=docker&label=Layers)

# nordlynx-proxy

[NordVPN client's version](https://nordvpn.com/fr/blog/nordvpn-linux-release-notes/) or [changelog](
https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn/nordvpn_4.3.1_amd64.changelog): 4.3.1 (17-12-2025)

As of 2024/11/18, nordvpn reorganized its repository and removed pre 3.17.0 versions. privileged mode is now required for the container when using latest or <env>-debian.

Starting from 2025/07/14, two new docker tags are added <version>-debian, <version>-ubuntu.
Debian based image requires privilege mode, please note that running privileged container is a risk.
Ubuntu based image do not require privilege mode.
Latest tag is based on debian as previously.

you may set env var NORDVPN_VERSION to install a specific nordvpn package downgrade during setup process. 

Warning 1: login process is sometimes unstable: 
```
It's not you, it's us. We're having trouble reaching our servers. If the issue persists, please contact our customer support.
```

Warning 2: login through token is preferred:
```
Logging in via ‘--legacy’, ‘--username’, and ‘--password’ flags is deprecated. Use ‘nordvpn login' or ‘nordvpn login --nordaccount’ to log in via browser. Alternatively, you can use ‘nordvpn login --token’ to log in with a generated token.
```

Warning 3: at the moment, the container is not set to run with generated wireguard config file. (healthcheck, start checks, switch from NordVPN to WireGuard tools).

### Description
This is a NordVPN docker container, based on debian bookworm, that connects to the NordVPN recommended servers using the NordVPN Linux client. It starts a SOCKS5 proxy server (dante) and a HTTP proxy server to use it as a NordVPN gateway. When using wireguard tools, useful to extract wireguard configuration , 317 MB of additional disk space will be used. (nordlynx-proxy-wg image is built to compare sizes). OpenVPN and NordLynx technology are available through NordVPN settings technology. Whenever the connection is lost, the NordVPN client has a killswitch to obliterate the connection.

### Exporting WireGuard config
If environment variable `GENERATE_WIREGUARD_CONF=true` is set, the WireGuard configuration is saved to `/etc/wireguard/wg0.conf` when connecting.
This file can be exported then re-used to setup a plain WireGuard connection. 

### VPN tests:
* https://www.dnsleaktest.com
* https://ipleak.net
* https://browserleaks.com/webrtc

**Please note that WebRTC will leak your real IP. You need to disable WebRTC  or install nordvpn's browser extension.**
https://browserleaks.com/webrtc#howto-disable-webrtc

## What is this?
This image is a variation of nordvpn-proxy. The latter is based on OpenVPN. 
The NordVPN client application replaces OpenVPN. NordVPN's version of [WireGuard](https://nordvpn.com/blog/wireguard-simplicity-efficiency/) is [NordLynx](https://nordvpn.com/blog/nordlynx-protocol-wireguard/).

You can then expose port `1080` from the container to access the VPN connection via the SOCKS5 proxy, or use the `8888` http's proxy port.

To sum up, this container:
* Opens the best connection to NordVPN using NordVPN's API results according to your criteria. [NordVPN recommended](https://nordvpn.com/servers/tools/)
* Starts a HTTP proxy that routes `eth0:8888` to `eth0:1080` (socks server) with [tinyproxy](https://tinyproxy.github.io/).
* Starts a SOCKS5 proxy that routes `eth0:1080` to `tun0/nordlynx` with [dante-server](https://www.inet.no/dante/).
* NordVPN DNS servers perform resolution, by default.
* Uses supervisor to handle services easily.

The main advantages are:
- You get the best recommendation for each combination of parameters (country, groups, protocol).
- You can select OpenVPN or NordLynx protocol.
- Use of NordVPN app features (Killswitch, CyberSec, ....).


Please note, that to avoid DNS problems when the DNS service is on the same host, /etc/resolv.conf is set to Cloudflare DNS (1.1.1.1).
The DNS above is only used during startup (to check the latest NordVPN version). NordVPN DNS is set when VPN connection is up.
```
# Generated by NordVPN
nameserver 103.86.96.100
nameserver 103.86.99.100
```

## Usage
The container may use environment variables to select a server, otherwise the best recommended server is selected:
See environment variables to get all available options or [NordVPN support](https://support.nordvpn.com/Connectivity/Linux/1325531132/Installing-and-using-NordVPN-on-Debian-Ubuntu-Raspberry-Pi-Elementary-OS-and-Linux-Mint.htm#Settings).

Adding 
``` docker
sysclts:
 - net.ipv6.conf.all.disable_ipv6=1 # disable ipv6
 ```
Might be needed, if NordVPN cannot change the settings itself.

## Environment options
* ANALYTICS: [off/on], default on, send anonymous aggregate data: crash reports, OS version, marketing performance, and feature usage data
* TECHNOLOGY: [NordLynx](https://support.nordvpn.com/hc/en-us/articles/19564565879441-What-is-NordLynx)/[OpenVPN](https://support.nordvpn.com/hc/en-us/articles/19683394.3.161-OpenVPN-connection-on-NordVPN)/[nordwhisper](https://nordvpn.com/blog/nordwhisper-protocol/), default: NordLynx (wireguard like)
* PROTOCOL: udp (default), tcp. Can only be used with TECHNOLOGY=OpenVPN.
* [OBFUSCATE](https://nordvpn.com/features/obfuscated-servers/): [off/on], default off, hide vpn's use.
* CONNECT: [country]/[server]/[country_code]/[city] or [country] [city], if none provide you will connect to argentina server.
* [COUNTRY](https://api.nordvpn.com/v1/servers/countries): define the exit country, default argentina.
* [GROUP](https://api.nordvpn.com/v1/servers/groups): Default P2P, value: Africa_The_Middle_East_And_India, Asia_Pacific, Europe, Onion_Over_VPN, P2P, Standard_VPN_Servers, The_Americas, although many categories are possible, p2p seems to be more adapted.
* NORDVPN_LOGIN: email or token (as of 25-07-21, service credentials are not allowed).
* NORDVPN_PASS: pass or empty when using token
* CYBER_SEC, default off
* KILLERSWITCH, default on
* DNS: change dns
* PORTS: add ports to allow
* LOCAL_NETWORK: add subnet to allow, multiple values possible net1, net2, net3, ....
* DOCKER_NET: optional, docker CIDR extracted from container ip if not set. 
* TINYUSER: optional, enforces authentication over tinyproxy when set with TINYPASS. 
* TINYPASS: optional, enforces authentication over tinyproxy when set with TINYUSER. 

### NordVPN Authentication
As of 23-12-2022, login with username and password are deprecated, as well as legacy. Username and password logins are allowed in the container, but may not be allowed by NordVPN. Login with a token is highly recommended. Tokens can be generated in your [NordAccount](https://my.nordaccount.com/dashboard/nordvpn).

### docker-compose example with env variables explained
```yaml
services:
  proxy:
    image: edgd1er/nordlynx-proxy:latest
    restart: unless-stopped
    ports:
      - "1080:1080"
      - "8888:8888"
    sysctls:
      - net.ipv6.conf.all.disable_ipv6=1 # disable ipv6
    cap_add:
      - NET_ADMIN               # Required
    environment:
      - TZ=America/Chicago
      #- CONNECT= #Optional, overrides COUNTRY, specify country+server number for example: uk715
      - COUNTRY=de #Set NordVPN server country to connect to.
      - GROUP=P2P #Africa_The_Middle_East_And_India, Asia_Pacific, Europe, Onion_Over_VPN, P2P, Standard_VPN_Servers, The_Americas
      #- KILLERSWITCH=on #Optional, on by default, kill switch is a feature helping you prevent unprotected access to the internet when your traffic doesn't go through a NordVPN server.
      #- CYBER_SEC=off #CyberSec is a feature protecting you from ads, unsafe connections and malicious sites
      #- TECHNOLOGY=NordLynx #OpenVPN or NordLynx
      #- PROTOCOL=udp #Optional, udp (default) or tcp. Can only be used with TECHNOLOGY=OpenVPN.
      #- IPV6=off #Optional, off by default, on/off available, off disables IPV6 in NordVPN app
      #- NORDVPN_LOGIN=<email or token> #Not required if using secrets
      #- NORDVPN_PASS=<pass> #Not required if using secrets or token in above `NORDVPN_LOGIN=token`
      #- DEBUG=0 #(0/1) activate debug mode for scripts, dante, tinyproxy
      - LOCAL_NETWORK=192.168.1.0/24 #LAN subnet to route through proxies and vpn.
      #- TINYUSER: optional, enforces authentication over tinyproxy when set with TINYPASS.
      #- TINYPASS: optional, enforces authentication over tinyproxy when set with TINYUSER.
      #- TINYLOGLEVEL=error #Optional, default error: Critical (least verbose), Error, Warning, Notice, Connect (to log connections without info's noise), Info
      - TINYLOGOUTPUT=file # Optional, stdout or file.
      #- TINYPORT=8888 #define tinyport inside the container, optional, 8888 by default,
      #- DANTE_LOGLEVEL="error" #Optional, error by default, available values: connect disconnect error data
      - DANTE_LOGOUTPUT=file #Optional, stdout, null, file (/var/log/dante.log=
      #- DANTE_DEBUG=0 # Optional, 0-9
      #- GENERATE_WIREGUARD_CONF=true #write /etc/wireguard/wg0.conf if true
    secrets:
      - NORDVPN_CREDS # token, 1 line only
      - TINY_CREDS # username on line 1, password on line 2

secrets:
    NORDVPN_CREDS:
        file: ./nordvpn_creds #file with username/token in 1st line, passwd in 2nd line.
    TINY_CREDS:
        file: ./tiny_creds #file with username/password in 1st line, passwd in 2nd line.
```

### Secrets

Nordvpn and tinyproxy credentials may be available throught secrets (/run/secrets/nordvpn_creds, /run/secrets/tiny_creds)
In the setup scripts, secrets values override any env values. Secrets names are fixed values: NORDVPN_CREDS, TINY_CREDS.

file: ./nordvpn_creds #file with username/token in 1st line, passwd in 2nd line.
file: ./tiny_creds #file with username/password in 1st line, passwd in 2nd line.

### Troubleshoot
Enter the container: `docker compose exec lynx bash`

Several aliases are available:
* checkhttp: get external ip through http proxy and vpn. should be the same as `checkip`
* checksocks: get external ip through socks proxy and vpn. should be the same as `checkip`
* checkip: get external ip. should be the same as `getcheck`
* checkvpn: print protection status as seen by nordvpn's client.
* getcheck: get information as ip from nordvpn client.
* getdante: print socks proxy configuration
* gettiny: print http proxy configuration
* getversion: install nordvpn specific version, allow downgrades eg 3.17.0, 3.17.1, ...

From times to times, nordvpn app is bugged, installing another version (downgrade) may be a workaround.

Sometimes docker won't start the container as the file resolv.conf is locked cannot be modified anymore.
This problem occurs since nordvpn'client 3.19.

to restart the container, remove i attribute on host container's resolv.conf
```chattr -i /var/lib/docker/containers/<container-hash>/resolv.conf```