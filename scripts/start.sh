#!/usr/bin/env bash
set -x

rm -rf /tmp/*

declare -p | grep -Ev '^declare -[[:alpha:]]*r' > /container.env

###########################[ SUPERVISOR SCRIPTS ]###############################

if [ ! -f /etc/app_configured ]; then
    mkdir -p /etc/supervisor/conf.d
cat << EOF > /etc/supervisor/conf.d/deluged.conf
[program:deluged]
command=/bin/su -s /bin/bash -c "ulimit -Sn 65535 && SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt SSL_CERT_DIR=/etc/ssl/certs TERM=xterm /usr/bin/deluged -c /torrents/config/deluge/ -d --loglevel=info -l /torrents/config/log/deluged.log" deluge
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
    
cat << EOF > /etc/supervisor/conf.d/deluge-web.conf
[program:deluge-web]
command=/bin/su -s /bin/bash -c "ulimit -Sn 65535 && TERM=xterm /usr/bin/deluge-web -d -c /torrents/config/deluge/ --loglevel=info" deluge
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
    
cat << EOF > /etc/supervisor/conf.d/delugecheck.conf
[program:delugecheck]
command=/scripts/delugecheck
autostart=true
autorestart=true
priority=90
startsecs=10
startretries=9999  
stdout_events_enabled=true
stderr_events_enabled=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

cat << EOF > /etc/supervisor/conf.d/nginx.conf
[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"
autostart=true
autorestart=true
priority=3
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

if [ ! -f /torrents/config/deluge/plugins/YaRSS2-2.1.5.egg ]; then
    cp /sources/YaRSS2-2.1.5.egg /torrents/config/deluge/plugins/YaRSS2-2.1.5.egg
fi

if [ ! -f /torrents/config/deluge/plugins/ltConfig-2.0.0.egg ]; then
    cp /sources/ltConfig-2.0.0.egg /torrents/config/deluge/plugins/ltConfig-2.0.0.egg
fi

if [ ! -f /torrents/config/deluge/plugins/ExtractorPlus-1.6.2.egg ]; then
    cp /sources/ExtractorPlus-1.6.2.egg /torrents/config/deluge/plugins/ExtractorPlus-1.6.2.egg
fi

if [ ! -f /torrents/config/deluge/plugins/AutoRemovePlus-0.6.4.dev0.egg ]; then
    cp /sources/AutoRemovePlus-0.6.8.egg /torrents/config/deluge/plugins/AutoRemovePlus-0.6.8.egg
fi

if [ ! -f /etc/app_configured ]; then
    if [ ! -f /torrents/config/deluge/core.conf ]; then
        cp /sources/core.conf /torrents/config/deluge
        cp /sources/web.conf /torrents/config/deluge
        cp /sources/hostlist.conf.1.2 /torrents/config/deluge
        cp /sources/ltconfig.conf /torrents/config/deluge/ltconfig.conf

        sed -i 's#FIRST_PORT#'${FIRST_PORT}'#g' /torrents/config/deluge/core.conf
        sed -i 's#LAST_PORT#'${FIRST_PORT}'#g' /torrents/config/deluge/core.conf
        sed -i 's#DAEMON_PORT#'${DAEMON_PORT}'#g' /torrents/config/deluge/core.conf
        sed -i 's#DAEMON_PORT#'${DAEMON_PORT}'#g' /torrents/config/deluge/web.conf
        sed -i 's#DAEMON_PORT#'${DAEMON_PORT}'#g' /torrents/config/deluge/hostlist.conf.1.2
        /scripts/deluge-pass.py /torrents/config/deluge ${DELUGE_PASSWORD}
        cat /torrents/config/deluge/auth | grep "${DELUGE_USERNAME}" || echo "${DELUGE_USERNAME}:${DELUGE_PASSWORD}:10" >> /torrents/config/deluge/auth
        rm -rf /torrents/config/deluge/*.bak

        if [[ ! $(cat /torrents/config/deluge/core.conf | grep 'ltConfig') || ! $(cat /torrents/config/deluge/core.conf | grep 'YaRSS2') ]]; then
            sed -i -z -E 's#"enabled_plugins": [^]]*#"enabled_plugins": \[\n    "AutoAdd",\n    "Scheduler",\n    "Label",\n    "Notifications",\n    "ltConfig",\n    "YaRSS2"\n  #g' /torrents/config/deluge/core.conf
        fi
        
        if ! grep -q 'torrents' /torrents/config/deluge/autoadd.conf; then
            cp /sources/autoadd.conf /torrents/config/deluge/autoadd.conf
        fi
    else
        # Recreated container with existing data (update): keep the customer's
        # preferences and only point Deluge at the ports assigned to this container.
        cp /sources/web.conf /torrents/config/deluge
        cp /torrents/config/deluge/core.conf /torrents/config/deluge/core.conf.backup
        if [ ! -f /torrents/config/deluge/ltconfig.conf ]; then
            cp /sources/ltconfig.conf /torrents/config/deluge/ltconfig.conf
        fi
        sed -i 's#"daemon_port": [0-9]*,#"daemon_port": '${DAEMON_PORT}',#g' /torrents/config/deluge/core.conf
        sed -i -z -E 's#"listen_ports": [^]]*#"listen_ports": \[\n    '${FIRST_PORT}',\n    '${FIRST_PORT}'\n  #g' /torrents/config/deluge/core.conf
        sed -i 's#DAEMON_PORT#'${DAEMON_PORT}'#g' /torrents/config/deluge/web.conf
        /scripts/deluge-pass.py /torrents/config/deluge ${DELUGE_PASSWORD}
        cp /sources/hostlist.conf.1.2 /torrents/config/deluge
        sed -i 's#DAEMON_PORT#'${DAEMON_PORT}'#g' /torrents/config/deluge/hostlist.conf.1.2
        sed -i -z 's#"127.0.0.1",\s*\n\s*[0-9]*,#"127.0.0.1",\n      '${DAEMON_PORT}',#g' /torrents/config/deluge/hostlist.conf.1.2.old
        sed -i -z 's#"127.0.0.1",\s*\n\s*[0-9]*,#"127.0.0.1",\n      '${DAEMON_PORT}',#g' /torrents/config/deluge/hostlist.conf
    fi
else
    cp /sources/web.conf /torrents/config/deluge
    sed -i 's#"daemon_port": [0-9]*,#"daemon_port": '${DAEMON_PORT}',#g' /torrents/config/deluge/core.conf
    sed -i -z -E 's#"listen_ports": [^]]*#"listen_ports": \[\n    '${FIRST_PORT}',\n    '${FIRST_PORT}'\n  #g' /torrents/config/deluge/core.conf
    sed -i 's#DAEMON_PORT#'${DAEMON_PORT}'#g' /torrents/config/deluge/web.conf
    /scripts/deluge-pass.py /torrents/config/deluge ${DELUGE_PASSWORD}
    sed -i -z 's#"127.0.0.1",\s*\n\s*[0-9]*,#"127.0.0.1",\n      '${DAEMON_PORT}',#g' /torrents/config/deluge/hostlist.conf.1.2
    sed -i -z 's#"127.0.0.1",\s*\n\s*[0-9]*,#"127.0.0.1",\n      '${DAEMON_PORT}',#g' /torrents/config/deluge/hostlist.conf.1.2.old
    sed -i -z 's#"127.0.0.1",\s*\n\s*[0-9]*,#"127.0.0.1",\n      '${DAEMON_PORT}',#g' /torrents/config/deluge/hostlist.conf
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

setcap cap_net_bind_service=+ep /usr/bin/python3.12

exec /usr/bin/supervisord -n -c /etc/supervisord.conf