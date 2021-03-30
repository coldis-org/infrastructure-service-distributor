# From HAProxy image.
FROM haproxy:2.3.7

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

# Installs dig.
RUN apt-get update -y && \
	apt-get install -y dnsutils && \
	apt-get clean -y && \
	rm -rf /var/lib/apt/lists/*
	
# Configures syslog.
RUN apt-get update -y && \
	apt-get install -y rsyslog && \
	apt-get clean -y && \
	rm -rf /var/lib/apt/lists/* && \
	mkdir -p /etc/rsyslog.d && \
	touch /var/log/haproxy.log && \
	ln -sf /dev/stdout /var/log/haproxy.log
COPY rsyslog.conf /etc/rsyslog.d/

# Copies the scripts.
RUN mkdir -p /opt/haproxy-script
COPY script /opt/haproxy-script
RUN chmod -R 755 /opt/haproxy-script && \
	ln -s /opt/haproxy-script/*.sh /usr/bin && \
	for FILE in /usr/bin/haproxy*.sh; \
	do \
		mv -- "${FILE}" "${FILE%.sh}"; \
	done

# Configures scheduled jobs (intranet updates)
COPY cron /etc/cron.d
RUN chmod -R 0644 /etc/cron.d/ && \
	crontab /etc/cron.d/haproxy_jobs

# Copies the configuration.
COPY config/ /usr/local/etc/haproxy/

# Service config folder.
ENV SERVICE_CONFIG_DIRECTORY=/usr/local/etc/haproxy/service
RUN mkdir -p /usr/local/etc/haproxy/service

# Entrypoint with multiple configuration directories.
ENTRYPOINT [ "haproxy_init" ]
CMD [ "-W", "-f", "/usr/local/etc/haproxy", "-f", "/usr/local/etc/haproxy/service" ]

