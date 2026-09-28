#!/bin/sh

# Materializes the certificate held in CERT_FULLCHAIN and CERT_PRIVKEY into
# ${CERT_ENV_DIR}/{fullchain,privkey}.pem, on tmpfs by default so the key never reaches
# the container writable layer.
#
# Must be SOURCED (. nginx_install_certs_from_env), never executed: it unsets the
# certificate variables, and a child process would lose the unset. Two things depend
# on it:
#   - the entrypoint dumps the environment into /etc/docker_env for cron. A multi line
#     PEM there leaks the key and breaks the file, since cron sources it.
#   - nginx_variables runs envsubst with every environment variable over every config
#     file.
#
# Doing nothing when the variables are empty keeps the certbot based setup untouched.

# Installs the certificate held in the environment.
nginx_install_certs_from_env() {

	DEBUG=${DEBUG:=false}
	CERT_ENV_DIR=${CERT_ENV_DIR:=/dev/shm/certs}

	${DEBUG} && echo "nginx_install_certs_from_env: [DEBUG] Running"
	${DEBUG} && echo "nginx_install_certs_from_env: [DEBUG] CERT_ENV_DIR=${CERT_ENV_DIR}"

	# Nothing to do when no certificate is held in the environment.
	if [ -z "${CERT_FULLCHAIN:-}" ] || [ -z "${CERT_PRIVKEY:-}" ]
	then
		${DEBUG} && echo "nginx_install_certs_from_env: [DEBUG] No CERT_FULLCHAIN/CERT_PRIVKEY set. Skipping."
		return 0
	fi

	# Writes the certificate.
	mkdir -p "${CERT_ENV_DIR}"
	printf '%s\n' "${CERT_FULLCHAIN}" > "${CERT_ENV_DIR}/fullchain.pem"
	printf '%s\n' "${CERT_PRIVKEY}" > "${CERT_ENV_DIR}/privkey.pem"
	chmod 700 "${CERT_ENV_DIR}"
	chmod 644 "${CERT_ENV_DIR}/fullchain.pem"
	chmod 600 "${CERT_ENV_DIR}/privkey.pem"

	echo "nginx_install_certs_from_env: [INFO] Installed certificate at '${CERT_ENV_DIR}'."

	# Clears the certificate from the environment.
	unset CERT_FULLCHAIN CERT_PRIVKEY

}
