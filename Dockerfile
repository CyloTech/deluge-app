FROM ubuntu:noble

ARG DEBIAN_FRONTEND=noninteractive

# Fix for "Tracker status: Invalid Argument" should be removed when fixed upstream
# this was version libtorrent-rasterbar10_1.2.1+daily10045+33d006d+201911220604~ubuntu18.04.1_amd64.deb

ADD sources /sources
ADD scripts /scripts

RUN apt update && apt-get install -y adduser && userdel -r ubuntu || true && \
    adduser --system --disabled-password --home /home/deluge --shell /sbin/nologin --group --uid 1000 deluge && \
    apt update && apt install -y software-properties-common && \
    add-apt-repository "deb https://ppa.launchpadcontent.net/deluge-team/stable/ubuntu noble main" && \
    apt update && apt install -y \
    p7zip \
    unrar \
    unzip \
    supervisor \
    libcap2-bin \
    libgeoip-dev \
    locales \
    python3-pip \
    python3-venv \
    jq \
    curl \
    python3-gi \
    python3-gi-cairo \
    deluge*=2.2.0* \
    python3-urllib3 \
    nginx \
    libnginx-mod-http-ndk \
    libnginx-mod-http-lua

RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install deluge-client

# Generate locale, copy supervisord config, set permissions, clean up
RUN locale-gen en_US.UTF-8 && \
    cp /sources/supervisord.conf /etc/supervisord.conf && \
    cp /sources/nginx.conf /etc/nginx/nginx.conf && \
    chmod -R +x /scripts && \
    setcap cap_net_bind_service=+ep /usr/bin/python3.12 && \
    apt clean && \
    apt autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# Ports
EXPOSE 80

CMD [ "/scripts/start.sh" ]
