# From Debian.
FROM debian:stretch-slim

RUN	set -x \
	&& apt-get -y update \
	&& apt-get install -y pgbouncer libpam-ldap \
	&& apt-get purge -y --auto-remove \
	&& rm -rf /var/lib/apt/lists/*

# Copies the scripts.
RUN mkdir -p /opt/pgbouncer-script
COPY script /opt/pgbouncer-script
RUN chmod -R 755 /opt/pgbouncer-script && \
	ln -s /opt/pgbouncer-script/*.sh /usr/bin && \
	for FILE in /usr/bin/pgbouncer*.sh; \
	do \
		mv -- "${FILE}" "${FILE%.sh}"; \
	done

# Copies the configuration files.
ENV CERT_PATH=/etc/ssl/certs \
	TMP_CONF=/tmp/config \
	CONFIG_DIR=/etc/pgbouncer
RUN mkdir -p ${CERT_PATH} ${TMP_CONF} ${CONFIG_DIR}
COPY config/pgbouncer.ini ${TMP_CONF}
RUN chown -R postgres ${CERT_PATH} ${TMP_CONF} ${CONFIG_DIR}

# Copies the LDAP files.
COPY config/pam_ldap.conf /etc

# Entrypoint.
ENTRYPOINT [ "pgbouncer_init" ]







