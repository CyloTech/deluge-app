#!/usr/bin/env bash
set -x

###########################[ SUPERVISOR SCRIPTS ]###############################

if [ ! -f /etc/app_configured ]; then
    mkdir -p /etc/supervisor/conf.d
cat << EOF >> /etc/supervisor/conf.d/deluged.conf
[program:deluged]
command=/bin/su -s /bin/bash -c "TERM=xterm /usr/bin/deluged -c /torrents/config/deluge/ -d --loglevel=info -l /torrents/config/log/deluged.log" deluge
autostart=true
autorestart=true
priority=1
stdout_events_enabled=true
stderr_events_enabled=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

cat << EOF >> /etc/supervisor/conf.d/deluge-web.conf
[program:deluge-web]
command=/bin/su -s /bin/bash -c "TERM=xterm /usr/bin/deluge-web -c /torrents/config/deluge/ --loglevel=info" deluge
autostart=true
autorestart=true
priority=2
stdout_events_enabled=true
stderr_events_enabled=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF
fi

###########################[ DELUGE SETUP ]###############################

if [ ! -f /etc/app_configured ]; then
    mkdir -p /torrents/downloading
    mkdir -p /torrents/completed
    mkdir -p /torrents/config/deluge
    mkdir -p /torrents/config/deluge/plugins
    mkdir -p /torrents/config/deluge/plugins/.python-eggs
    mkdir -p /torrents/config/log
    mkdir -p /torrents/config/torrents
    mkdir -p /torrents/watch

    cp /sources/core.conf /torrents/config/deluge
    cp /sources/web.conf /torrents/config/deluge
    sed -i 's#LISTENING_PORT#'${LISTENING_PORT}'#g' /torrents/config/deluge/core.conf
    sed -i 's#DAEMON_PORT#'${DAEMON_PORT}'#g' /torrents/config/deluge/core.conf
    sed -i 's#DAEMON_PORT#'${DAEMON_PORT}'#g' /torrents/config/deluge/web.conf

    /scripts/deluge-pass.py /torrents/config/deluge ${DELUGE_PASSWORD}

    cat /torrents/config/deluge/auth | grep "${DELUGE_USERNAME}" || echo "${DELUGE_USERNAME}:${DELUGE_PASSWORD}:10" >> /torrents/config/deluge/auth

    chown -R deluge:deluge /torrents
fi

###########################[ MARK INSTALLED ]###############################

if [ ! -f /etc/app_configured ]; then
    touch /etc/app_configured
    curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST "https://api.cylo.io/v1/apps/installed/$INSTANCE_ID"
fi

exec /usr/bin/supervisord -n -c /etc/supervisord.conf