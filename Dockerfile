FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ARG S6_OVERLAY_VERSION=3.1.6.2

RUN apt-get update && apt-get install -y \
    curl gnupg xz-utils apt-transport-https iproute2 libmagic1 libyaml-0-2 openssh-server \
    && curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --dearmor -o /usr/share/keyrings/wazuh.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
        > /etc/apt/sources.list.d/wazuh.list \
    && apt-get update \
    && apt-get install -y wazuh-agent=4.14.3-1 \
    && curl -L -o /tmp/suricata.deb https://github.com/ADORSYS-GIS/wazuh-plugins/releases/download/suricata-v0.5.3/suricata-8.0.2-linux-amd64.deb \
    && (dpkg -i /tmp/suricata.deb || apt-get install -f -y) \
    && rm /tmp/suricata.deb \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install s6-overlay
RUN curl -L -o /tmp/s6-overlay-noarch.tar.xz \
      https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz \
    && curl -L -o /tmp/s6-overlay-x86_64.tar.xz \
      https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz \
    && tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
    && tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz \
    && rm /tmp/s6-overlay-*.tar.xz

# s6 service definitions
COPY s6-rc.d /etc/s6-overlay/s6-rc.d
RUN chmod +x /etc/s6-overlay/s6-rc.d/*/run /etc/s6-overlay/s6-rc.d/*/finish /etc/s6-overlay/s6-rc.d/*/up 2>/dev/null || true

# Configs
COPY volumes/wazuh-agent/ossec.conf /var/ossec/etc/ossec.conf
COPY volumes/suricata/suricata.yaml /etc/suricata/suricata.yaml

# Create Suricata runtime directories
RUN mkdir -p /opt/wazuh/suricata/var/log/suricata && \
    mkdir -p /opt/wazuh/suricata/var/lib/suricata/cache/sgh

ENTRYPOINT ["/init"]