# From Apache image.
FROM httpd:2.4.48

# Sets locale and UTF-8 charset.
ENV TZ=America/Sao_Paulo \
	LANG_NAME=pt_BR \
	LANG_FILE=pt_BR.UTF-8 \
	LANG=pt_BR.utf8 \
	LANGUAGE=pt_BR:pt
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

# User.
ENV APACHE_USER=httpd
RUN	groupadd ${APACHE_USER} && \
	useradd ${APACHE_USER} -g ${APACHE_USER}

# Installs cron.	
RUN apt-get update -y && \
	apt-get install -y cron dnsutils && \
	apt-get clean -y && \
	rm -rf /var/lib/apt/lists/*
	
# Installs certbot.
RUN apt-get update -y && \
	apt-get install -y certbot python-certbot-apache && \
	(certbot certonly --non-interactive --agree-tos || true) && \
	apt-get clean -y && \
	rm -rf /var/lib/apt/lists/*
	
# Installs modules.
RUN apt-get update -y && \
	apt-get install -y libapache2-mod-security2 apache2-utils linux-libc-dev && \
	mkdir -p /var/log/apache2 && \
	mkdir -p /var/cache/apache && \
	mkdir -p /usr/local/apache2/static && \
	chown ${APACHE_USER}:${APACHE_USER} -R /var/log/apache2 /var/cache/apache /usr/local/apache2/static && \
	chmod 755 -R /var/log/apache2 /var/cache/apache /usr/local/apache2/static && \
	cp /etc/modsecurity/unicode.mapping /usr/local/apache2/conf/extra/ && \
	cp /usr/lib/apache2/modules/mod_security2.so /usr/local/apache2/modules/ && \
	apt-get clean -y && \
	rm -rf /var/lib/apt/lists/*
	
# Copies configuration files.
RUN rm -Rf /usr/local/apache2/conf/extra/*.conf /usr/local/apache2/conf/mime /usr/local/apache2/conf/magic
COPY config/ /usr/local/apache2/conf/

# Copies the scripts.
RUN mkdir -p /opt/apache-script
COPY script /opt/apache-script
RUN chmod -R 755 /opt/apache-script && \
	ln -s /opt/apache-script/*.sh /usr/bin && \
	for FILE in /usr/bin/apache*.sh; \
	do \
		mv -- "${FILE}" "${FILE%.sh}"; \
	done
	
# Configures scheduled jobs (cert and intranet updates)
COPY cron /etc/cron.d
RUN chmod -R 0644 /etc/cron.d/ && \
	crontab /etc/cron.d/apache_jobs

# Sets static resources folder.
COPY static/ /usr/local/apache2/htdocs/
RUN chown ${APACHE_USER}:${APACHE_USER} -R /usr/local/apache2/htdocs/

# Hostname. Should be override.
ENV HOST_NAME=localhost \
	INTRANET_HOST_NAME=localhost
	
# MPM config.
ENV HTTPD_SERVER_LIMIT=17\
	HTTPD_START_SERVERS=17\
	HTTPD_MAX_CONNECTIONS_PER_CHILD=74789\
	HTTPD_THREADS_PER_CHILD=67\
	HTTPD_THREAD_LIMIT=67\
	HTTPD_MIN_SPARE_THREADS=1139\
	HTTPD_MAX_SPARE_THREADS=1139\
	HTTPD_MAX_REQUEST_WORKERS=1139\
	HTTPD_MAX_MEM_FREE=32768\
	HTTPD_LISTEN_BACK_LOG=3071\
	HTTPD_LISTEN_CORES_BUCKETS_RATIO=8\
	HTTPD_GRACEFUL_SHUTDOWN_TIMEOUT=30

# Command.
ENTRYPOINT [ "apache_start" ]
CMD [ "httpd-foreground" ]

