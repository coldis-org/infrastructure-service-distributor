# From Nginx image.
ARG NGINX_VERSION=1.27.4

# Build.
FROM nginx:${NGINX_VERSION} as build

RUN apt update \
	&& apt full-upgrade -y \
	&& apt-get install -y --no-install-recommends \
	wget \
	gcc \
	make \
	cmake \
	build-essential \
	autoconf \
	automake \
	libtool \
	libcurl4-openssl-dev \
	liblua5.3-dev \
	libfuzzy-dev \
	ssdeep \
	gettext \
	pkg-config \
	libpcre3 \
	libpcre3-dev \
	libxml2 \
	libxml2-dev \
	libcurl4 \
	libgeoip-dev \
	libyajl-dev \
	doxygen \
	libpcre2-16-0 \
	libpcre2-dev \
	libpcre2-posix3 \
	zlib1g-dev \
	git \
	unzip \
	uuid-dev \	
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /sources

# Mod security.
ARG MODSEC_VERSION=3.0.13
RUN wget --quiet https://github.com/owasp-modsecurity/ModSecurity/releases/download/v${MODSEC_VERSION}/modsecurity-v${MODSEC_VERSION}.tar.gz \
	&& tar -xvzf modsecurity-v${MODSEC_VERSION}.tar.gz \
	&& rm modsecurity-v${MODSEC_VERSION}.tar.gz \
	&& mv *modsecurity* modsecurity \
	&& cd modsecurity \
	&& ./build.sh \
	&& ./configure \
	&& make install \
	&& cd ..
	
# VTS.
ARG VTS_VERSION=0.2.3
RUN wget --quiet https://github.com/vozlt/nginx-module-vts/archive/refs/tags/v${VTS_VERSION}.tar.gz \
	&& tar -xvzf v${VTS_VERSION}.tar.gz \
	&& rm v${VTS_VERSION}.tar.gz \
	&& mv *nginx-module-vts* nginx-module-vts 

# Nginx.
ARG MODSEC_NGINX_VERSION=1.0.3
RUN wget --quiet https://github.com/SpiderLabs/ModSecurity-nginx/releases/download/v${MODSEC_NGINX_VERSION}/modsecurity-nginx-v${MODSEC_NGINX_VERSION}.tar.gz \
	&& tar -xvzf modsecurity-nginx-v${MODSEC_NGINX_VERSION}.tar.gz \
	&& rm modsecurity-nginx-v${MODSEC_NGINX_VERSION}.tar.gz \
	&& mv *modsecurity-nginx* modsecurity-nginx \
	&& wget --quiet http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz \
	&& tar -xvzf nginx-${NGINX_VERSION}.tar.gz \
	&& rm nginx-${NGINX_VERSION}.tar.gz \
	&& cd ./nginx-${NGINX_VERSION} \
	&& ./configure --with-debug --with-compat --with-http_v2_module --add-dynamic-module=../modsecurity-nginx --add-dynamic-module=../nginx-module-vts \
	&& make modules \
	&& cp objs/ngx_http_modsecurity_module.so /etc/nginx/modules/ \
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
COPY --from=build /lib/ /lib/
COPY --from=build /usr/lib/ /usr/lib/
COPY --from=build /usr/local/lib/ /usr/local/lib/
COPY --from=build /etc/nginx/modules/ngx_http_modsecurity_module.so /etc/nginx/modules/ngx_http_modsecurity_module.so
COPY --from=build /etc/modsecurity.d/unicode.mapping /etc/modsecurity.d/unicode.mapping
COPY --from=build /etc/nginx/modules/ngx_http_vhost_traffic_status_module.so /etc/nginx/modules/ngx_http_vhost_traffic_status_module.so

# Sets locale and UTF-8 charset.
ENV TZ=America/Sao_Paulo \
	LANG_NAME=en_US \
	LANG_FILE=en_US.UTF-8 \
	LANG=en_US.utf8 \
	LANGUAGE=en_US:us \
	LC_ALL=en_US
RUN apt-get update -y \
	&& apt-get purge -y locales \
	&& apt-get install -y locales \
	&& rm /usr/share/locale/locale.alias \
	&& ln -s /etc/locale.alias /usr/share/locale/locale.alias \
	&& localedef -i ${LANG_NAME} -c -f UTF-8 -A /usr/share/locale/locale.alias ${LANG_FILE} \
	&& cp /usr/share/zoneinfo/${TZ} /etc/localtime \
	&& apt-get purge -y locales \
	&& apt-get clean -y \
	&& rm -rf /var/lib/apt/lists/*

# Installs cron.
RUN apt-get update -y \
	&& apt-get install -y cron dnsutils wget \
	&& apt-get clean -y \
	&& rm -rf /var/lib/apt/lists/*

# Installs certbot.
RUN apt-get update -y \
	&& apt-get install -y certbot python3-certbot-nginx \
	&& (certbot certonly --non-interactive --agree-tos || true) \
	&& openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048 \
	&& apt-get clean -y \
	&& rm -rf /var/lib/apt/lists/*

# Configures scheduled jobs (cert and intranet updates)
COPY cron /etc/cron.d
RUN chmod -R 0644 /etc/cron.d/ \
	&& crontab /etc/cron.d/nginx_jobs

# Copies the scripts.
RUN mkdir -p /opt/nginx-script
COPY script /opt/nginx-script
RUN chmod -R 755 /opt/nginx-script \
	&& ln -s /opt/nginx-script/*.sh /usr/bin \
	&& for FILE in /usr/bin/nginx*.sh; \
	do \
		mv -- "${FILE}" "${FILE%.sh}"; \
	done

# Copies configuration.
RUN rm -f /etc/nginx/conf.d/* \
	&& mkdir -p /etc/nginx/vhost.d /etc/nginx/stream.d /var/cache/nginx/
COPY config/modsecurity /etc/modsecurity.d
COPY config/nginx /etc/nginx

# Create dir to populate later
RUN mkdir -p /etc/nginx/upstream.d

# Changes default permissions.
RUN chown -R nginx /var/cache/nginx/ /usr/share/nginx/ /etc/nginx/ /etc/modsecurity.d/

ENV	CERTBOT_PORT=80\
	ACCESSLOG=/dev/null\
	ERRORLOG=/dev/stderr\
	METRICSLOG=/dev/stdout\
	LOG_BUFFER=3m\
	LOG_FLUSH=30s\
	LOG_LEVEL=warn\
	DNS_SERVER=\
	CONNECTION_TIMEOUT=20s\
	TIMEOUT=50s\
	SERVER_NAME=localhost\
	PROCESSES=\
	PROCESSES_PROC_PERC=\
	CONNECTIONS=\
	CONNECTIONS_MEM_PERC=1000\
	KEEPALIVE_TIMEOUT=1m\
	KEEPALIVE_REQUESTS=\
	KEEPALIVE_REQUESTS_MEM_PERC=200\
	MAX_KEEPALIVE_REQUESTS=20000\
	AIO_REQUESTS=16384\
	THREADS=\
	THREADS_PROC_PERC=3000\
	MAX_THREADS=256\
	THREAD_QUEUE=\
	THREAD_QUEUE_MEM_PERC=3000\
	MODSEC_AUDIT_LOG=Off\
	NO_CERT_RENEW=true\
	CONF_HOST_NAME=localhost\
	AVAILABLE_NETS=intranet\
	LOCALNET_IPS=172.16.0.0/16,172.17.0.0/16\
	REQLIMIT_STATUS=418\
	REQLIMIT_BAN_TIME=300\
	REQLIMIT_ZONE_SIZE=100m\
	DEFAULT_REQLIMIT_RATIO=100r/m\
	DEFAULT_TRUSTED_REQLIMIT_RATIO=4000r/m

ENTRYPOINT ["nginx_entrypoint"]
CMD ["nginx", "-g", "daemon off;"]


