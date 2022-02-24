# From Nginx image.
ARG NGINX_VERSION=1.21.6

# Build.
FROM nginx:${NGINX_VERSION} as build
ARG MODSEC_VERSION=3.0.6

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
	automake \
	cmake \
	doxygen \
	g++ \
	git \
	libcurl4-gnutls-dev \
	libgeoip-dev \
	liblua5.3-dev \
	libpcre++-dev \
	libtool \
	libxml2-dev \
	make \
	ruby \
	wget \
	zlib1g-dev \
	libpcre3 \
	libpcre3-dev \
	unzip \
	uuid-dev \
	build-essential \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /sources

RUN git clone https://github.com/LMDB/lmdb --branch LMDB_0.9.29 --depth 1 \
	&& make -C lmdb/libraries/liblmdb install

RUN git clone https://github.com/lloyd/yajl --branch 2.1.0 --depth 1 \
	&& cd yajl \
	&& ./configure \
	&& make install

RUN wget --quiet https://github.com/ssdeep-project/ssdeep/releases/download/release-2.14.1/ssdeep-2.14.1.tar.gz \
	&& tar -xvzf ssdeep-2.14.1.tar.gz \
	&& cd ssdeep-2.14.1 \
	&& ./configure \
	&& make install

# pagespeed
ARG NPS_VERSION=1.13.35.2
RUN wget --quiet https://github.com/apache/incubator-pagespeed-ngx/archive/v${NPS_VERSION}-stable.tar.gz && \
	tar -xvzf v${NPS_VERSION}-stable.tar.gz && \
	mv *pagespeed-ngx* pagespeed-nginx && \
	cd pagespeed-nginx && \
	wget --quiet https://dl.google.com/dl/page-speed/psol/${NPS_VERSION}-x64.tar.gz && \
	tar -xvzf ${NPS_VERSION}-x64.tar.gz 

# vts
RUN git clone git://github.com/vozlt/nginx-module-vts.git

RUN git clone https://github.com/SpiderLabs/ModSecurity --branch v${MODSEC_VERSION} --depth 1 \
	&& cd ModSecurity \
	&& ./build.sh \
	&& git submodule init \
	&& git submodule update \
	&& ./configure --with-yajl=/sources/yajl/build/yajl-2.1.0/ \
	&& make install

# We use master
RUN git clone -b master --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git \
	&& wget --quiet http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz \
	&& tar -xzf nginx-${NGINX_VERSION}.tar.gz \
	&& cd ./nginx-${NGINX_VERSION} \
	&& ./configure --with-debug --with-compat --add-dynamic-module=../ModSecurity-nginx --add-dynamic-module=../pagespeed-nginx --add-dynamic-module=../nginx-module-vts \
	&& make modules \
	&& cp objs/ngx_http_modsecurity_module.so /etc/nginx/modules/ \
	&& cp objs/ngx_pagespeed.so /etc/nginx/modules/ \
	&& cp objs/ngx_http_vhost_traffic_status_module.so /etc/nginx/modules/\
	&& mkdir /etc/modsecurity.d \
	&& wget --quiet https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/unicode.mapping \
	-O /etc/modsecurity.d/unicode.mapping

# From Nginx.
FROM nginx:${NGINX_VERSION}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV LD_LIBRARY_PATH=/lib:/usr/lib:/usr/local/lib
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
	ca-certificates \
	libcurl4-gnutls-dev \
	liblua5.3 \
	libxml2 \
	moreutils \
	&& rm -rf /var/lib/apt/lists/* \
	&& apt-get clean \
	&& mkdir /etc/nginx/ssl

# Copies previous configuration.
COPY --from=build /usr/local/modsecurity/ /usr/local/modsecurity/
COPY --from=build /usr/local/lib/ /usr/local/lib/
COPY --from=build /etc/nginx/modules/ngx_http_modsecurity_module.so /etc/nginx/modules/ngx_http_modsecurity_module.so
COPY --from=build /etc/modsecurity.d/unicode.mapping /etc/modsecurity.d/unicode.mapping
COPY --from=build /etc/nginx/modules/ngx_pagespeed.so /etc/nginx/modules/ngx_pagespeed.so
COPY --from=build /etc/nginx/modules/ngx_http_vhost_traffic_status_module.so /etc/nginx/modules/ngx_http_vhost_traffic_status_module.so

# Sets locale and UTF-8 charset.
ENV TZ=America/Sao_Paulo \
	LANG_NAME=en_US \
	LANG_FILE=en_US.UTF-8 \
	LANG=en_US.utf8 \
	LANGUAGE=en_US:us \
	LC_ALL=en_US
RUN apt-get update -y && \
	apt-get purge -y locales && \
	apt-get install -y locales && \
	rm /usr/share/locale/locale.alias && \
	ln -s /etc/locale.alias /usr/share/locale/locale.alias && \
	localedef -i ${LANG_NAME} -c -f UTF-8 -A /usr/share/locale/locale.alias ${LANG_FILE} && \
	cp /usr/share/zoneinfo/${TZ} /etc/localtime && \
	apt-get purge -y locales && \
	apt-get clean -y && \
	rm -rf /var/lib/apt/lists/*

# Installs cron.
RUN apt-get update -y && \
	apt-get install -y cron dnsutils wget && \
	apt-get clean -y && \
	rm -rf /var/lib/apt/lists/*

# Installs certbot.
RUN apt-get update -y && \
	apt-get install -y certbot python3-certbot-nginx && \
	(certbot certonly --non-interactive --agree-tos || true) && \
	openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048 && \
	apt-get clean -y && \
	rm -rf /var/lib/apt/lists/*

# Configures scheduled jobs (cert and intranet updates)
COPY cron /etc/cron.d
RUN chmod -R 0644 /etc/cron.d/ && \
	crontab /etc/cron.d/nginx_jobs

# Copies the scripts.
RUN mkdir -p /opt/nginx-script
COPY script /opt/nginx-script
RUN chmod -R 755 /opt/nginx-script && \
	ln -s /opt/nginx-script/*.sh /usr/bin && \
	for FILE in /usr/bin/nginx*.sh; \
	do \
		mv -- "${FILE}" "${FILE%.sh}"; \
	done

# Copies configuration.
RUN rm -f /etc/nginx/conf.d/* && \
	mkdir -p /etc/nginx/vhost.d /etc/nginx/stream.d /var/cache/nginx/ /var/cache/pagespeed

COPY config/modsecurity /etc/modsecurity.d
COPY config/nginx /etc/nginx

# Changes default permissions.
RUN chown -R nginx /var/cache/nginx/ /var/cache/pagespeed/ /usr/share/nginx/ /etc/nginx/ /etc/modsecurity.d/

ENV	CERTBOT_PORT=80\
	ACCESSLOG=/dev/null\
	ERRORLOG=/dev/stderr\
	METRICSLOG=/dev/stdout\
	LOG_BUFFER=512k\
	LOG_FLUSH=17s\
	LOG_LEVEL=warn\
	DNS_SERVER=\
	CONNECTION_TIMEOUT=11s\
	TIMEOUT=45s\
	SERVER_NAME=localhost\
	PROCESSES=auto\
	CONNECTIONS=131070\
	AIO_REQUESTS=511\
	THREADS=511\
	THREAD_QUEUE=262140\
	MODSEC_AUDIT_LOG=Off\
	NO_CERT_RENEW=true\
	CONF_HOST_NAME=localhost

ENTRYPOINT ["nginx_entrypoint"]
CMD ["nginx", "-g", "daemon off;"]


