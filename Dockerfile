FROM debian:buster-slim

ARG aptcacher
ARG VERSION=3.12.0-1
ARG TZ=America/Chicag

LABEL maintainer="edgd1er <edgd1er@htomail.com>" \
      org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="Ripper" \
      org.label-schema.description="Provides VPN through NordVpn application." \
      org.label-schema.url="https://hub.docker.com/r/edgd1er/nordlynx-proxy" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/edgd1er/nordlynx-proxy" \
      org.label-schema.version=$VERSION \
      org.label-schema.schema-version="1.0"

ENV TZ=${TZ}
ENV DEBIAN_FRONTEND=noninteractive

COPY etc/ /etc/
COPY app/ /app/

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
#add apt-cacher setting if present:
#hadolint ignore=DL3018,DL3008
RUN if [[ -n "${aptcacher}" ]]; then echo "Acquire::http::Proxy \"http://${aptcacher}:3142\";" >/etc/apt/apt.conf.d/01proxy && \
    echo "Acquire::https::Proxy \"http://${aptcacher}:3142\";" >>/etc/apt/apt.conf.d/01proxy ; fi; \
    apt-get update && export DEBIAN_FRONTEND=non-interactive && \
    apt-get -o Dpkg::Options::="--force-confold" install --no-install-recommends -qqy supervisor wget curl jq \
    ca-certificates tzdata dante-server net-tools tinyproxy\
    # nordvpn requirements
    iproute2 iptables readline-common dirmngr gnupg gnupg-l10n gnupg-utils gpg gpg-agent gpg-wks-client \
    gpg-wks-server gpgconf gpgsm libassuan0 libksba8 libnpth0 libreadline7 libsqlite3-0 lsb-base pinentry-curses   && \
    wget -nv -t10 -O /tmp/nordrepo.deb https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/nordvpn-release_1.0.0_all.deb && \
    apt-get install -qqy --no-install-recommends /tmp/nordrepo.deb && apt-get update && \
    apt-get install -qqy --no-install-recommends -y nordvpn="${VERSION}" && \
    apt-get remove -y wget nordvpn-release && find /etc/apt/ -iname "*.list" -exec cat {} \; && echo && \
    mkdir -p /run/nordvpn && chmod a+x /app/*.sh && \
    addgroup --system vpn && useradd -lNms /usr/bash -u "${NUID:-1000}" -G nordvpn,vpn nordclient  && \
    apt-get clean all && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    if [[ -n "${aptcacher}" ]]; then rm /etc/apt/apt.conf.d/01proxy; fi;

HEALTHCHECK --interval=5m --timeout=20s --start-period=1m CMD /app/healthcheck.sh

# Start supervisord as init system
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
