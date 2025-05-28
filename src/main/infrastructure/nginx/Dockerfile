# From Nginx image.
ARG NGINX_VERSION=1.27.4
ARG BUILD_PROC=16 

# From Debian.
FROM coldis/infrastructure-os:1.0.0 as debian

# Build.
FROM nginx:${NGINX_VERSION} as build

# Sets the workdir.
WORKDIR /sources

# Mod security.
ARG MODSEC_VERSION=3.0.13
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		automake \
		cmake \
		doxygen \
		g++ \
		git \
		libcurl4-gnutls-dev \
		libfuzzy-dev \
		liblua5.3-dev \
		libpcre3-dev \
		libpcre2-dev \
		libtool \
		libxml2-dev \
		libmaxminddb-dev \
		libyajl-dev \
		make \
		patch \
		pkg-config \
		ruby \
		zlib1g-dev \
		wget \
	&& wget --quiet https://github.com/owasp-modsecurity/ModSecurity/releases/download/v${MODSEC_VERSION}/modsecurity-v${MODSEC_VERSION}.tar.gz \
	&& tar -xvzf modsecurity-v${MODSEC_VERSION}.tar.gz \
	&& rm modsecurity-v${MODSEC_VERSION}.tar.gz \
	&& mv *modsecurity* modsecurity \
	&& cd modsecurity \
	&& ./build.sh \
	&& ./configure \
	&& make install 
	
# VTS.
ARG VTS_VERSION=0.2.3
RUN wget --quiet https://github.com/vozlt/nginx-module-vts/archive/refs/tags/v${VTS_VERSION}.tar.gz \
	&& tar -xvzf v${VTS_VERSION}.tar.gz \
	&& rm v${VTS_VERSION}.tar.gz \
	&& mv *nginx-module-vts* nginx-module-vts 

# Modsec module.
ARG MODSEC_NGINX_VERSION=1.0.3
RUN wget --quiet https://github.com/SpiderLabs/ModSecurity-nginx/releases/download/v${MODSEC_NGINX_VERSION}/modsecurity-nginx-v${MODSEC_NGINX_VERSION}.tar.gz \
	&& tar -xvzf modsecurity-nginx-v${MODSEC_NGINX_VERSION}.tar.gz \
	&& rm modsecurity-nginx-v${MODSEC_NGINX_VERSION}.tar.gz \
	&& mv *modsecurity-nginx* modsecurity-nginx \
	&& mkdir /etc/modsecurity.d \
	&& wget --quiet https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/unicode.mapping \
	-O /etc/modsecurity.d/unicode.mapping

# Devel kit module.
ARG NDK_VERSION=v0.3.1
RUN wget --quiet https://github.com/simpl/ngx_devel_kit/archive/refs/tags/${NDK_VERSION}.tar.gz \
    && tar -xvzf ${NDK_VERSION}.tar.gz \
    && rm ${NDK_VERSION}.tar.gz \
    && mv *ngx_devel_kit* devel-kit
	
# Set-misc module.
ARG SET_MISC_VERSION=0.33
RUN wget --quiet https://github.com/openresty/set-misc-nginx-module/archive/refs/tags/v${SET_MISC_VERSION}.tar.gz \
    && tar -xvzf v${SET_MISC_VERSION}.tar.gz \
    && rm v${SET_MISC_VERSION}.tar.gz \
    && mv *set-misc* set-misc
	
# Builds NGINX.
RUN wget --quiet http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz \
	&& tar -xvzf nginx-${NGINX_VERSION}.tar.gz \
	&& rm nginx-${NGINX_VERSION}.tar.gz \
	&& cd ./nginx-${NGINX_VERSION} \
	&& ./configure \
		--with-debug \
		--with-compat \
		--with-http_v2_module \
		--add-dynamic-module=../modsecurity-nginx \
		--add-dynamic-module=../nginx-module-vts \
		--add-dynamic-module=../devel-kit \
		--add-dynamic-module=../set-misc \
	&& make -j${BUILD_PROC} \
	&& make install \
	&& mkdir -p /etc/nginx/modules \
	&& cp objs/*.so /etc/nginx/modules/

# From Nginx.
FROM nginx:${NGINX_VERSION}

# Installs basic packages.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
	&& apt-get full-upgrade -y \
	&& apt-get install -y --no-install-recommends \
	ca-certificates \
	libcurl4-gnutls-dev \
	libxml2 \
	moreutils \
	&& rm -rf /var/lib/apt-get/lists/* \
	&& apt-get clean \
	&& mkdir /etc/nginx/ssl

# Copies previous configuration.
COPY --from=build /lib/ /lib/
COPY --from=build /usr/lib/ /usr/lib/
COPY --from=build /usr/local/ /usr/local/
COPY --from=build /etc/nginx/modules/ /etc/nginx/modules/
COPY --from=build /etc/modsecurity.d/unicode.mapping /etc/modsecurity.d/unicode.mapping

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
	&& rm -rf /var/lib/apt-get/lists/*

# Installs cron.
RUN apt-get update -y \
	&& apt-get install -y cron dnsutils wget \
	&& apt-get clean -y \
	&& rm -rf /var/lib/apt-get/lists/*

# Installs certbot.
RUN apt-get update -y \
	&& apt-get install -y certbot python3-certbot-nginx \
	&& (certbot certonly --non-interactive --agree-tos || true) \
	&& openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048 \
	&& apt-get clean -y \
	&& rm -rf /var/lib/apt-get/lists/*

# Configures scheduled jobs (cert and intranet updates)
COPY cron /etc/cron.d
RUN chmod -R 0644 /etc/cron.d/

# Installs syslog and copies configuration.
RUN apt-get update -y \
    && apt-get install -y rsyslog \
    && apt-get clean -y \
    && rm -rf /var/lib/apt-get/lists/*
COPY config/rsyslog.conf /etc/rsyslog.conf	

# Copies the scripts.
COPY --from=debian /opt/os-script /opt/os-script
COPY --from=debian /usr/bin/os* /usr/bin
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
	&& mkdir -p /etc/nginx/vhost.d /etc/nginx/stream.d /var/cache/nginx/ /etc/nginx/upstream.d
COPY config/modsecurity /etc/modsecurity.d
COPY config/nginx /etc/nginx
COPY html /usr/share/nginx/html

# Changes default permissions.
RUN chown -R nginx.nginx /var/cache/nginx/ /usr/share/nginx/ /etc/nginx/ /etc/modsecurity.d/

# Environment variables.
ENV	CERTBOT_PORT=80\
	CERT_SELF_DOMAIN=/C=BR/ST=SaoPaulo/L=SaoPaulo/O=SuperSim/OU=Com/OU=Br\
	CERT_SELF_CNS=client\
	CERT_SELF_OWN_CN=*.supersim.com.br\
	CERT_UPDATE_SCHEDULE="0 0 * * *"\
	CONFIG_UPDATE_SCHEDULE="* * * * *"\
	ACCESSLOG=/dev/null\
	METRICSLOG=/dev/stdout\
	ERRORLOG=syslog:server=unix:/dev/log,facility=local7,tag=nginx\
	LOG_BUFFER_MB=5\
	LOG_FLUSH_MILLIS=10000\
	LOG_LEVEL=warn\
	DNS_SERVER=\
	CONNECTION_TIMEOUT=15s\
	TIMEOUT=30s\
	PROXY_TIMEOUT=120s\
	WORKER_SHUTDOWN_TIMEOUT=10m\
	SERVER_NAME=localhost\
	PROCESSES=\
	PROCESSES_PROC_PERC=\
	CONNECTIONS=\
	CONNECTIONS_MEM_PERC=1000\
	KEEPALIVE_TIMEOUT=1m\
	KEEPALIVE_REQUESTS=\
	KEEPALIVE_REQUESTS_MEM_PERC=200\
	MAX_KEEPALIVE_REQUESTS=3000\
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
	REQLIMIT_STATUS=429\
	REQLIMIT_BAN_TIME=300\
	REQLIMIT_ZONE_SIZE=100m\
	DEFAULT_REQLIMIT_BURST=30\
	DEFAULT_REQLIMIT_RATIO=10r/s\
	DEFAULT_TRUSTED_REQLIMIT_RATIO=4000r/m\
	MAX_REQLIMIT_RATIO=10000r/m\
	INTERNAL_SYNC_CONF_HOST_NAME=web-config.intranet.supersim.com.br\
	FALLBACK_PORT=6767\
	NOCACHE_VALUE="no-store, no-cache"
	
ENTRYPOINT ["nginx_entrypoint"]
CMD ["nginx", "-g", "daemon off;"]


