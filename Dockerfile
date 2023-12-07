FROM debian:bookworm-slim
ARG aptcacher
ARG VERSION=3.16.9
ARG TZ=America/Chicago
ARG WG=false

LABEL maintainer="edgd1er <edgd1er@htomail.com>" \
      org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="nordlynx-proxy" \
      org.label-schema.description="Provides VPN through NordVpn application." \
      org.label-schema.url="https://hub.docker.com/r/edgd1er/nordlynx-proxy" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/edgd1er/nordlynx-proxy" \
      org.label-schema.version=$VERSION \
      org.label-schema.schema-version="1.0"

ENV TZ=${TZ}
ENV DEBIAN_FRONTEND=noninteractive
ENV GENERATE_WIREGUARD_CONF=false
ENV ANALYTICS=on
ENV KILLERSWITCH=on
ENV CYBER_SEC=off
ENV TECHNOLOGY=nordlynx
ENV PROTOCOL=udp
ENV OBFUSCATE=off
ENV IPV6=off
ENV DEBUG=0
ENV TINYLOGLEVEL=error
ENV TINYPORT=8888
ENV DANTE_LOGLEVEL="error"
ENV DANTE_ERRORLOG=/dev/null
ENV DANTE_DEBUG=0
ENV GENERATE_WIREGUARD_CONF=false

COPY etc/ /etc/
COPY app/ /app/

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
#add apt-cacher setting if present:
#hadolint ignore=DL3018,DL3008
RUN if [[ -n "${aptcacher}" ]]; then echo "Acquire::http::Proxy \"http://${aptcacher}:3142\";" >/etc/apt/apt.conf.d/01proxy \
    && echo "Acquire::https::Proxy \"http://${aptcacher}:3142\";" >>/etc/apt/apt.conf.d/01proxy ; fi \
    && apt-get update && export DEBIAN_FRONTEND=non-interactive \
    && apt-get -o Dpkg::Options::="--force-confold" install --no-install-recommends -qqy supervisor wget curl jq \
    ca-certificates tzdata dante-server net-tools tinyproxy zstd \
    # nordvpn requirements
    iproute2 iptables readline-common dirmngr gnupg gnupg-l10n gnupg-utils gpg gpg-agent gpg-wks-client \
    gpg-wks-server gpgconf gpgsm libassuan0 libksba8 libnpth0 libreadline8 libsqlite3-0 lsb-base pinentry-curses \
    #check conf template with package conf
    && diff /etc/tinyproxy/tinyproxy.conf /etc/tinyproxy.conf.tmpl || true \
    && diff /etc/dante/danted.conf /etc/danted.conf.tmpl || true \
    #wireguard
    && if [[ ${WG} != false ]]; then apt-get -o Dpkg::Options::="--force-confold" install -y --no-install-recommends wireguard wireguard-tools; fi \
    && wget -nv -t10 -O /tmp/nordrepo.deb https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/nordvpn-release_1.0.0_all.deb \
    && apt-get install -qqy --no-install-recommends /tmp/nordrepo.deb && apt-get update \
    && apt-get install -qqy --no-install-recommends -y nordvpn="${VERSION}" \
    && apt-get remove -y wget nordvpn-release && find /etc/apt/ -iname "*.list" -exec cat {} \; && echo \
    && mkdir -p /run/nordvpn && chmod a+x /app/*.sh \
    && addgroup --system vpn && useradd -lNms /usr/bash -u "${NUID:-1000}" -G nordvpn,vpn nordclient \
    && echo "alias checkip='curl -sm 10 \"https://zx2c4.com/ip\";echo'" | tee -a ~/.bashrc \
    && echo "alias checkhttp='curl -sm 10 -x http://\${HOSTNAME}:\${WEBPROXY_PORT:-8888} \"https://ifconfig.me/ip\";echo'" | tee -a ~/.bashrc \
    && echo "alias checksocks='curl -sm10 -x socks5://\${HOSTNAME}:1080 \"https://ifconfig.me/ip\";echo'" | tee -a ~/.bashrc \
    && echo "alias checkvpn='curl -sm 10 \"https://api.nordvpn.com/vpn/check/full\" | jq -r .status'" | tee -a ~/.bashrc \
    && echo "alias getcheck='curl -sm 10 \"https://api.nordvpn.com/vpn/check/full\" | jq . '" | tee -a ~/.bashrc \
    && echo "alias gettiny='grep -vP \"(^$|^#)\" /etc/tinyproxy/tinyproxy.conf'" | tee -a ~/.bashrc \
    && echo "alias getdante='grep -vP \"(^$|^#)\" /etc/sockd.conf'" | tee -a ~/.bashrc \
    && echo "alias dltest='curl http://appliwave.testdebit.info/100M.iso -o /dev/null'" | tee -a ~/.bashrc \
    && apt-get clean all && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && if [[ -n "${aptcacher}" ]]; then rm /etc/apt/apt.conf.d/01proxy; fi;

HEALTHCHECK --interval=5m --timeout=20s --start-period=1m CMD /app/healthcheck.sh
WORKDIR /app

# Start supervisord as init system
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]