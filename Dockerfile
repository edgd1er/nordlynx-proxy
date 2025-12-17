ARG base=debian:13-slim
#ARG base=ubuntu:24.04
#hadolint ignore=DL3006
FROM ${base} AS base
ARG base
ARG aptcacher=""
ARG VERSION=4.3.0
ARG TZ=America/Chicago
ARG WG=false
ARG BUILD_DATE

LABEL maintainer="edgd1er <edgd1er@htomail.com>" \
      org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="nordlynx-proxy (${base})" \
      org.label-schema.description="Provides VPN through NordVpn application." \
      org.label-schema.url="https://hub.docker.com/r/edgd1er/nordlynx-proxy" \
      org.label-schema.vcs-url="https://github.com/edgd1er/nordlynx-proxy" \
      org.label-schema.version=$VERSION \
      org.label-schema.schema-version="1.0"

ENV TZ=${TZ}
ENV NORDVPN_VERSION=4.3.0
ENV DEBIAN_FRONTEND=noninteractive
ENV GENERATE_WIREGUARD_CONF=false
ENV ANALYTICS=off
ENV KILLERSWITCH=on
ENV CYBER_SEC=off
ENV TECHNOLOGY=nordlynx
ENV PROTOCOL=udp
ENV OBFUSCATE=off
ENV IPV6=off
ENV DEBUG=0
ENV TINYLOGLEVEL=error
ENV TINYLOGOUTPUT=stdout
ENV TINYPORT=8888
ENV DANTE_LOGLEVEL=error
ENV DANTE_LOGOUTPUT=/dev/null
ENV DANTE_DEBUG=0
ENV GENERATE_WIREGUARD_CONF=false
ENV TECHNOLOGY=nordlynx
ENV OBFUSCATE=off
ENV PROTOCOL=udp
ENV COUNTRY=argentina
ENV GROUP=P2P

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
#add apt-cacher setting if present:
#hadolint ignore=DL3018,DL3008
#hadolint ignore=DL3018,DL3008,SC2086
RUN if [[ -n "${aptcacher}" ]]; then echo "Acquire::http::Proxy \"http://${aptcacher}:3142\";" >/etc/apt/apt.conf.d/01proxy; \
    echo "Acquire::https::Proxy \"http://${aptcacher}:3142\";" >>/etc/apt/apt.conf.d/01proxy ; fi; \
    # allow to install resolvconf \
    echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections \
    # trixie backports \
    && if [[ "${base}" =~ (trixie|13) ]]; then echo -e "Types: deb deb-src\nURIs: http://deb.debian.org/debian\nSuites: trixie-backports\nComponents: main contrib non-free non-free-firmware\nSigned-By: /usr/share/keyrings/debian-archive-keyring.gpg\nEnabled: yes">/etc/apt/sources.list.d/debian-backports.sources \
    && echo -e "Types: deb deb-src\nURIs: http://deb.debian.org/debian\nSuites: forky\nComponents: main contrib non-free non-free-firmware\nSigned-By: /usr/share/keyrings/debian-archive-keyring.gpg\nEnabled: yes">/etc/apt/sources.list.d/debian-testing.sources \
    && apt-get update && apt-get -o Dpkg::Options::="--force-confold" install -t forky --no-install-recommends -qqy  dante-server libassuan9 e2fsprogs; DS="" ; else DS="dante-server libassuan0"; fi \
    && apt-get update && export DEBIAN_FRONTEND=non-interactive && apt-get -o Dpkg::Options::="--force-confold" install --no-install-recommends -qqy supervisor wget curl jq \
    ca-certificates tzdata net-tools tinyproxy zstd ${DS}\
    # nordvpn requirements \
    iproute2 iptables readline-common dirmngr gnupg gnupg-l10n gnupg-utils gpg gpg-agent gpg-wks-client \
    gpg-wks-server gpgconf gpgsm libksba8 libsqlite3-0 lsb-base pinentry-curses \
    # wireguard \
    wireguard-tools \
    && echo "BASE: ${base}, ${WG}, ${TB}" \
    && if [[ ${WG} != false ]]; then apt-get -o Dpkg::Options::="--force-confold" install -y --no-install-recommends wireguard wireguard-tools; fi \
    && apt-get clean all && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
RUN mkdir -p /run/nordvpn \
    && sh <(curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh) -n -v ${VERSION} \
    && addgroup --system vpn \
    # && useradd -lNms /usr/bin/bash -u "${NUID:-1000}" -G nordvpn,vpn nordclient \
    && usermod -aG nordvpn,vpn root \
    && apt-get clean all && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && if [[ -f /etc/apt/apt.conf.d/01proxy ]]; then rm /etc/apt/apt.conf.d/01proxy; fi;

#add apps and conf
COPY etc/ /etc/
COPY --chmod=0755 app/ /app/

#check conf template with package conf
RUN diff /etc/tinyproxy/tinyproxy.conf /etc/tinyproxy.conf.tmpl || true \
    && diff /etc/dante/danted.conf /etc/danted.conf.tmpl || true \
    # wireguard
    && echo "alias checkip='curl -sm 10 \"https://zx2c4.com/ip\";echo'" | tee -a ~/.bashrc \
    && echo "alias checkhttp='TCF=/run/secrets/TINY_CREDS; [[ -f \${TCF} ]] && TCREDS=\"\$(sed -n \"1p\" \${TCF}):\$(sed -n \"2p\" \${TCF})@\" || TCREDS=\"\";curl -4 -sm 10 -x http://\${TCREDS}\${HOSTNAME}:\${WEBPROXY_PORT:-8888} \"https://ifconfig.me/ip\";echo'" | tee -a ~/.bashrc \
    && echo "alias checksocks='TCF=/run/secrets/TINY_CREDS; [[ -f \${TCF} ]] && TCREDS=\"\$(sed -n \"1p\" \${TCF}):\$(sed -n \"2p\" \${TCF})@\" || TCREDS=\"\";curl -4 -sm10 -x socks5h://\${TCREDS}\${HOSTNAME}:1080 \"https://ifconfig.me/ip\";echo'" | tee -a ~/.bashrc \
    && echo "alias checkvpn='nordvpn status | grep -oP \"(?<=Status: ).*\"'" | tee -a ~/.bashrc \
    && echo "alias gettiny='grep -vP \"(^$|^#)\" /etc/tinyproxy/tinyproxy.conf'" | tee -a ~/.bashrc \
    && echo "alias getdante='grep -vP \"(^$|^#)\" /etc/danted.conf'" | tee -a ~/.bashrc \
    && echo "alias dltest='curl http://appliwave.testdebit.info/100M.iso -o /dev/null'" | tee -a ~/.bashrc \
    && echo "function getversion(){ apt-get update && apt-get install -y --allow-downgrades nordvpn=\${1:-3.16.9} && supervisorctl start start_vpn; }" | tee -a ~/.bashrc \
    && echo "function showversion(){ apt-cache show nordvpn |grep -oP '(?<=Version: ).+' | sort | awk 'NR==1 {first = \$0} END {print first\" - \"\$0; }'; }" | tee -a ~/.bashrc

HEALTHCHECK --interval=5m --timeout=20s --start-period=1m CMD /app/healthcheck.sh
WORKDIR /app
VOLUME /var/log/

# Start supervisord as init system
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]