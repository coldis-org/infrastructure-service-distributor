# From Debian.
FROM debian:11.7-slim
ENV DEBIAN_FRONTEND noninteractive

# Installs necessary libs to build pgbouncer.
RUN	set -x \
	&& apt-get -y update \
	&& apt-get install -y openssl ca-certificates gettext libevent-2.1-7 libssl1.1 libpam0g curl gcc pkgconf libevent-dev libssl-dev libpam0g-dev make \
	&& apt-get purge -y --auto-remove \
	&& rm -rf /var/lib/apt/lists/*

# Installs PG bouncer.
ENV PGBOUNCER_VERSION=1.21.0 \
	PGBOUNCER_BIN=/opt/pgbouncer \
	PGBOUNCER_CONFIG=/etc/pgbouncer \
	PGBOUNCER_LOGS=/var/log/pgbouncer \
	PGBOUNCER_SOCKET=/var/pgbouncer/socket \
	PGBOUNCER_CERTS=/etc/ssl/certs \
	PGBOUNCER_USER=postgres 
RUN mkdir -p ${PGBOUNCER_BIN} && \
	mkdir -p ${PGBOUNCER_CONFIG} && \
	mkdir -p ${PGBOUNCER_LOGS} && \
	mkdir -p ${PGBOUNCER_SOCKET} && \
	mkdir -p ${PGBOUNCER_CERTS} && \
	cd ${PGBOUNCER_BIN} && \
	curl -Lso  "${PGBOUNCER_BIN}/pgbouncer.tar.gz" "https://pgbouncer.github.io/downloads/files/${PGBOUNCER_VERSION}/pgbouncer-${PGBOUNCER_VERSION}.tar.gz"  && \
	tar -zxvf pgbouncer.tar.gz -C ${PGBOUNCER_BIN} --strip-components 1 && \
	rm ${PGBOUNCER_BIN}/pgbouncer.tar.gz
WORKDIR ${PGBOUNCER_BIN}

RUN	adduser ${PGBOUNCER_USER} && \
	./configure --prefix=/usr --with-pam && \
	make && \
	make install

# Removes tools used for building pgbouncer.
RUN	set -x \
	&& apt-get remove -y curl gcc pkgconf libevent-dev libssl-dev make \
	&& apt-get purge -y --auto-remove \
	&& rm -rf /var/lib/apt/lists/*

# Installs LDAP integration.
RUN	set -x \
	&& apt-get -y update \
	&& apt-get install -y libpam-ldap \
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
COPY config/pgbouncer.ini /etc/pgbouncer/
RUN chown -R ${PGBOUNCER_USER}:${PGBOUNCER_USER} ${PGBOUNCER_CERTS} ${PGBOUNCER_LOGS} ${PGBOUNCER_SOCKET} ${PGBOUNCER_CONFIG} ${PGBOUNCER_BIN} && \
	chmod -R 755 ${PGBOUNCER_LOGS}

# Copies the LDAP files.
COPY config/pam_ldap.conf /etc

# Env.
ENV MIN_POOL_SIZE=7\
	DEFAULT_POOL_SIZE=73\
	RESERVE_POOL_SIZE=5\
	MAX_USER_CONNECTIONS=19\
	MAX_DB_CONNECTIONS=93\
	MAX_CLIENT_CONN=739\
	POOL_MODE=session\
	PROCESSES=1

# Entrypoint.
ENTRYPOINT [ "pgbouncer_init" ]

