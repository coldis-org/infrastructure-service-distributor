# PgBouncer version.
ARG PGBOUNCER_VERSION=1.26.1

# Builds PgBouncer.
FROM alpine:3.24.3 AS build
ARG PGBOUNCER_VERSION
ARG PGBOUNCER_SHA256=00886a2994b4844cd37110970df777772cfc42a74c400522c82fba509a3f42d9
WORKDIR /sources
RUN apk add --no-cache build-base c-ares-dev curl libevent-dev openldap-dev openssl-dev pkgconf \
	&& curl -fsSLo pgbouncer.tar.gz "https://www.pgbouncer.org/downloads/files/${PGBOUNCER_VERSION}/pgbouncer-${PGBOUNCER_VERSION}.tar.gz" \
	&& echo "${PGBOUNCER_SHA256}  pgbouncer.tar.gz" | sha256sum -c - \
	&& tar -xzf pgbouncer.tar.gz --strip-components 1 \
	&& ./configure --prefix=/usr --with-cares --with-ldap \
	&& make -j"$(nproc)" pgbouncer

# From Alpine.
FROM alpine:3.24.3
ARG PGBOUNCER_VERSION

# Installs the runtime libraries, openssl (self-signed certificate), envsubst and the
# PostgreSQL client (used to RELOAD the admin console).
RUN apk add --no-cache c-ares ca-certificates gettext-envsubst libevent libldap openssl postgresql18-client

# Installs PG bouncer.
ENV PGBOUNCER_VERSION=${PGBOUNCER_VERSION} \
	PGBOUNCER_BIN=/opt/pgbouncer \
	PGBOUNCER_CONFIG=/etc/pgbouncer \
	PGBOUNCER_LOGS=/var/log/pgbouncer \
	PGBOUNCER_SOCKET=/var/pgbouncer/socket \
	PGBOUNCER_CERTS=/etc/ssl/certs \
	PGBOUNCER_USER=postgres
COPY --from=build /sources/pgbouncer ${PGBOUNCER_BIN}/pgbouncer
RUN mkdir -p ${PGBOUNCER_CONFIG} ${PGBOUNCER_LOGS} ${PGBOUNCER_SOCKET} ${PGBOUNCER_CERTS} \
	&& ln -s ${PGBOUNCER_BIN}/pgbouncer /usr/bin/pgbouncer \
	&& (id ${PGBOUNCER_USER} >/dev/null 2>&1 \
		|| (addgroup -S -g 70 ${PGBOUNCER_USER} && adduser -S -D -H -u 70 -G ${PGBOUNCER_USER} ${PGBOUNCER_USER}))
WORKDIR ${PGBOUNCER_BIN}

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

# Env.
# LDAP (search+bind): LDAP_URI is the server host, LDAP_USER the bind DN and LDAP_PASSWORD
# (no default) its password. $username in LDAP_SEARCH_FILTER is replaced by PgBouncer.
# REJECT_USERS (separated by ',' or ':') are refused before any LDAP round trip, and left
# out of the search so another spelling finds no entry either. LDAP_SCHEME=ldaps (with
# LDAP_PORT=636) or LDAP_TLS=1 (StartTLS) encrypt the LDAP connection; the server
# certificate is verified, against LDAPTLS_CACERT when its CA is not in the system store.
ENV MIN_POOL_SIZE=7\
	DEFAULT_POOL_SIZE=73\
	RESERVE_POOL_SIZE=5\
	MAX_USER_CONNECTIONS=19\
	MAX_DB_CONNECTIONS=93\
	MAX_CLIENT_CONN=739\
	POOL_MODE=session\
	PROCESSES=1\
	LDAP_URI=\
	LDAP_PORT=389\
	LDAP_SCHEME=\
	LDAP_TLS=\
	LDAP_BASE_DN=\
	LDAP_USER=\
	LDAP_SEARCH_FILTER="(&(objectClass=posixAccount)(cn=\$username))"\
	REJECT_USERS=\
	AUTH_HBA_FILE=/etc/pgbouncer/pgbouncer_hba.conf

# Entrypoint.
ENTRYPOINT [ "pgbouncer_init" ]
