FROM ubuntu
USER root

LABEL name="deluge"
LABEL version="2.0.3"

RUN adduser --system --disabled-password --home /home/deluge --shell /sbin/nologin --group --uid 1000 deluge

RUN apt update && \
    apt install -y software-properties-common && \
    add-apt-repository ppa:deluge-team/stable

RUN apt install -y \
    deluged \
    deluge-web \
    deluge-console \
    p7zip \
    unrar \
    unzip \
    supervisor \
    libcap2-bin \
    libgeoip-dev \
    locales \
    curl && \
    locale-gen en_US.UTF-8

# add local files
RUN setcap cap_net_bind_service=+ep /usr/bin/python3.6
ADD sources /sources
ADD sources/supervisord.conf /etc/supervisord.conf
ADD scripts/deluge-pass.py /scripts/deluge-pass.py
ADD scripts/start.sh /scripts/start.sh
RUN chmod -R +x /scripts
RUN groupmod -g 9999 nogroup
RUN usermod -g 9999 nobody
RUN usermod -u 9999 nobody
RUN usermod -g 9999 sync

RUN apt autoremove -y
RUN rm -rf /var/lib/apt/lists/*

# ports
EXPOSE 80

CMD [ "/scripts/start.sh" ]