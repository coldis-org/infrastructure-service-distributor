#!/bin/sh

# Default script behavior.
set -o errexit
#set -o pipefail

# Default paramterers.
DEBUG=false
DEBUG_OPT=
PGBOUNCER_PARAMETERS=
CERT_PATH=/etc/ssl/certs
CERT_FILE_PREFIX=coldis
CERT_INFO="/C=${CERT_C}/ST=${CERT_ST}/L=${CERT_L}/O=${CERT_O}/OU=${CERT_OU}/CN=${CERT_CN}"

# For each argument.
while :; do
	case ${1} in
		
		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
			;;

		# Other option.
		?*)
			PGBOUNCER_PARAMETERS="${PGBOUNCER_PARAMETERS} ${1}"
			;;

		# No more options.
		*)
			break

	esac 
	shift
done

# Using unavaialble variables should fail the script.
set -o nounset

# Enables interruption signal handling.
trap - INT TERM

# Print arguments if on debug mode.
${DEBUG} && echo  "Running 'haproxy_init'"

# Generates certificates.
openssl req -new -x509 -nodes -text -out ${CERT_PATH}/server.crt \
	-keyout ${CERT_PATH}/server.key -subj "${CERT_INFO}"
chmod og-rwx ${CERT_PATH}/server.key

# If there is no config file yet.
if [ ! -f ${CONFIG_DIR}/pgbouncer.ini ]
then
	# Copies the config files.
	cp -R ${TMP_CONF}/* ${CONFIG_DIR}/
	
	# For each configuratin file.
	for FILE in ${CONFIG_DIR}/*
	do 
		# Replaces variables in the files.
		envsubst < ${FILE} > ${FILE}
	done
fi

# If the database file does not exist.
if [ ! -f ${CONFIG_DIR}/database/database.ini ]
then

	# Creates it.
	mkdir -p ${CONFIG_DIR}/database
	touch ${CONFIG_DIR}/database/database.ini

fi

# Executes the init script.
${DEBUG} && echo "exec /opt/pgbouncer/pgbouncer ${QUIET:+-q} -u postgres ${CONFIG_DIR}/pgbouncer.ini"
exec /opt/pgbouncer/pgbouncer ${QUIET:+-q} -u postgres ${CONFIG_DIR}/pgbouncer.ini

