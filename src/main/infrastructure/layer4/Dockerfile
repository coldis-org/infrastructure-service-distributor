# From HAProxy image.
FROM haproxy:1.9.6

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

# Copies the scripts.
RUN mkdir -p /opt/haproxy-script
COPY script /opt/haproxy-script
RUN chmod -R 755 /opt/haproxy-script && \
	ln -s /opt/haproxy-script/*.sh /usr/bin && \
	for FILE in /usr/bin/haproxy*.sh; \
	do \
		mv -- "${FILE}" "${FILE%.sh}"; \
	done
	
# Copies the configuration.
COPY config/ /usr/local/etc/haproxy/

# Service config folder.
ENV SERVICE_CONFIG_DIRECTORY=persistent-config/service
RUN mkdir -p ${SERVICE_CONFIG_DIRECTORY}

# Entrypoint with multiple configuration directories.
ENTRYPOINT [ "haproxy_init", "-f", "/usr/local/etc/haproxy", "-f", "/usr/local/etc/haproxy/service" ]

