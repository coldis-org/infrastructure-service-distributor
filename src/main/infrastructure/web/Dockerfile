# From Apache image.
FROM owasp/modsecurity:3.0.3-apache

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

# Installs cron.	
RUN apt-get update -y && \
	apt-get install -y cron && \
	apt-get clean -y && \
	rm -rf /var/lib/apt/lists/*
	
# Installs certbot.
RUN apt-get update -y && \
	apt-get install -y certbot python-certbot-apache && \
	(certbot certonly --non-interactive --agree-tos || true) && \
	apt-get clean -y && \
	rm -rf /var/lib/apt/lists/*

# Installs security rules.
RUN apt-get update -y && \
	apt-get install -y wget unzip dnsutils && \
	mkdir -p /usr/local/apache2/conf/extra/crs && \
	wget "https://github.com/SpiderLabs/owasp-modsecurity-crs/archive/v3.1.1.zip" -O security.zip && \
	unzip security.zip -d /usr/local/apache2/conf/extra/crs && \
	rm -f security.zip && \
	TMP_DIR=`ls /usr/local/apache2/conf/extra/crs` && \
	mv /usr/local/apache2/conf/extra/crs/${TMP_DIR}/* /usr/local/apache2/conf/extra/crs/ && \
	rm -R /usr/local/apache2/conf/extra/crs/${TMP_DIR} && \
	apt-get remove -y wget unzip && \
	apt-get clean -y && \
	rm -rf /var/lib/apt/lists/*apache

# Copies configuration files.
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
RUN chown www-data.www-data -R /usr/local/apache2/htdocs/

# Hostname. Should be override.
ENV HOST_NAME=localhost \
	INTRANET_HOST_NAME=localhost	

# Command.
ENTRYPOINT [ "apache_start" ]
CMD [ "httpd-foreground" ]

