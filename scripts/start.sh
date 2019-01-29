#!/usr/bin/env bash
set -x

###########################[ SUPERVISOR SCRIPTS ]###############################

if [ ! -f /etc/app_configured ]; then
    mkdir -p /etc/supervisor/conf.d
cat << EOF >> /etc/supervisor/conf.d/deluged.conf
[program:deluged]
command=/bin/su -s /bin/bash -c "TERM=xterm && ulimit -Sn 65535 && /usr/bin/deluged -c /torrents/config/deluge/ -d --loglevel=info -l /torrents/config/log/deluged.log" deluge
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
fi

if [ ! -f /torrents/config/deluge/plugins/YaRSS2-1.4.3-py2.7.egg ]; then
    cp /sources/YaRSS2-1.4.3-py2.7.egg /torrents/config/deluge/plugins/YaRSS2-1.4.3-py2.7.egg
fi

if [ ! -f /torrents/config/deluge/plugins/ltConfig-0.3.1-py2.7.egg ]; then
    cp /sources/ltConfig-0.3.1-py2.7.egg /torrents/config/deluge/plugins/ltConfig-0.3.1-py2.7.egg
fi

if [ ! -f /torrents/config/deluge/ltconfig.conf ]; then
    cp /sources/ltconfig.conf /torrents/config/deluge/ltconfig.conf
fi

if [[ ! $(cat /torrents/config/deluge/core.conf | grep 'ltConfig') || ! $(cat /torrents/config/deluge/core.conf | grep 'YaRSS2') ]]; then
    sed -i -z -E 's#"enabled_plugins": [^]]*#"enabled_plugins": \[\n    "AutoAdd",\n    "Scheduler",\n    "Label",\n    "Notifications",\n    "ltConfig",\n    "YaRSS2"\n  #g' /torrents/config/deluge/core.conf
fi

if [ ! -f /torrents/config/deluge/core.conf ]; then
    cp /sources/core.conf /torrents/config/deluge
    cp /sources/web.conf /torrents/config/deluge
    cp /sources/hostlist.conf.1.2 /torrents/config/deluge

    /scripts/deluge-pass.py /torrents/config/deluge ${DELUGE_PASSWORD}
    cat /torrents/config/deluge/auth | grep "${DELUGE_USERNAME}" || echo "${DELUGE_USERNAME}:${DELUGE_PASSWORD}:10" >> /torrents/config/deluge/auth

    sed -i 's#FIRST_PORT#'${FIRST_PORT}'#g' /torrents/config/deluge/core.conf
    sed -i 's#LAST_PORT#'${LAST_PORT}'#g' /torrents/config/deluge/core.conf
    sed -i 's#DAEMON_PORT#'${DAEMON_PORT}'#g' /torrents/config/deluge/core.conf
    sed -i 's#DAEMON_PORT#'${DAEMON_PORT}'#g' /torrents/config/deluge/web.conf
    sed -i 's#DAEMON_PORT#'${DAEMON_PORT}'#g' /torrents/config/deluge/hostlist.conf.1.2
else
    sed -i 's#"daemon_port": [0-9]*,#"daemon_port": '${DAEMON_PORT}',#g' /torrents/config/deluge/core.conf
    sed -i -z -E 's#"listen_ports": [^]]*#"listen_ports": \[\n    '${FIRST_PORT}',\n    '${LAST_PORT}'\n  #g' /torrents/config/deluge/core.conf
    sed -i 's#127.0.0.1:[0-9]*#127.0.0.1:'${DAEMON_PORT}'#g' /torrents/config/deluge/web.conf
    sed -i -z 's#"127.0.0.1",\n\s*[0-9]*,#"127.0.0.1",\n      '${DAEMON_PORT}',#g' /torrents/config/deluge/hostlist.conf.1.2
fi

ls -d /torrents/* | grep -v home | xargs -d "\n" chown -R deluge:deluge

###########################[ MARK INSTALLED ]###############################

if [ ! -f /etc/app_configured ]; then
    touch /etc/app_configured
    until [[ $(curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST "https://api.cylo.io/v1/apps/installed/${INSTANCE_ID}" | grep '200') ]]
        do
        sleep 5
    done
fi

exec /usr/bin/supervisord -n -c /etc/supervisord.conf