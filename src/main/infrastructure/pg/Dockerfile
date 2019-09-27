# From PGBouncer.
FROM pgbouncer/pgbouncer:1.11.0

# Changes to root usr.
USER root

# Installs pam.
RUN apk --update --no-cache add \
	nss-pam-ldapd gettext

# Copies the configuration files.
ENV CERT_PATH=/etc/ssl/certs \
	TMP_CONF=/tmp/config \
	CONFIG_DIR=/etc/pgbouncer
RUN mkdir -p ${CERT_PATH} ${TMP_CONF} ${CONFIG_DIR}
COPY config ${TMP_CONF}
RUN chown -R postgres ${CERT_PATH} ${TMP_CONF} ${CONFIG_DIR}

# Copies the scripts.
RUN mkdir -p /opt/pgbouncer-script
COPY script /opt/pgbouncer-script
RUN chmod -R 755 /opt/pgbouncer-script && \
	ln -s /opt/pgbouncer-script/*.sh /usr/bin && \
	for FILE in /usr/bin/pgbouncer*.sh; \
	do \
		mv -- "${FILE}" "${FILE%.sh}"; \
	done
	
# Goes back to the postgres user.	
USER postgres

# Entrypoint.
ENTRYPOINT [ "/usr/bin/pgbouncer_init" ]
