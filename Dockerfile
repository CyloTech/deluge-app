FROM alpine:3.7

ENV PYTHON_EGG_CACHE="/torrents/config/deluge/plugins/.python-eggs"

RUN \
  addgroup -S deluge -g 1000 && \
  adduser -D -S -h /home/deluge -s /sbin/nologin -G deluge deluge -u 1000 && \
  echo "**** install build packages ****" && \
 apk add --no-cache --virtual=build-dependencies \
	g++ \
	gcc \
	libffi-dev \
	openssl-dev \
	py2-pip \
	python2-dev && \
 echo "**** install runtime packages ****" && \
 apk add --no-cache \
    supervisor \
    bash \
	ca-certificates \
	curl \
	libressl2.6-libssl \
	openssl \
	p7zip \
	unrar \
	libcap \
	unzip && \
 apk add --no-cache \
	--repository http://nl.alpinelinux.org/alpine/edge/testing \
	deluge && \
 echo "**** install pip packages ****" && \
 pip install --no-cache-dir -U \
	incremental \
	pip && \
 pip install --no-cache-dir -U \
	crypto \
	mako \
	markupsafe \
	pyopenssl \
	service_identity \
	six \
	twisted \
	zope.interface && \
 echo "**** cleanup ****" && \
 apk del --purge \
	build-dependencies && \
 rm -rf /root/.cache && \
 wget -q http://geolite.maxmind.com/download/geoip/database/GeoLiteCountry/GeoIP.dat.gz && \
 gunzip GeoIP.dat.gz && \
 mkdir -p /usr/share/GeoIP && \
 mv GeoIP.dat /usr/share/GeoIP/GeoIP.dat

# add local files

RUN setcap cap_net_bind_service=+ep /usr/bin/python2.7
ADD sources /sources
ADD sources/supervisord.conf /etc/supervisord.conf
ADD scripts/deluge-pass.py /scripts/deluge-pass.py
ADD scripts/start.sh /scripts/start.sh
RUN chmod -R +x /scripts
# ports
EXPOSE 80

CMD [ "/scripts/start.sh" ]