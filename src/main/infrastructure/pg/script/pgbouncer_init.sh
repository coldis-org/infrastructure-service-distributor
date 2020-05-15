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
RESET=${RESET:=false} 

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
${DEBUG} && echo  "Running 'pgbouncer_init'"

# Generates certificates.
openssl req -new -x509 -nodes -text -out ${CERT_PATH}/server.crt \
	-keyout ${CERT_PATH}/server.key -subj "${CERT_INFO}"
chmod og-rwx ${CERT_PATH}/server.key

# Copies the config files.
cp -R ${TMP_CONF}/* ${CONFIG_DIR}

# For each configuratin file.
for FILE in ${CONFIG_DIR}/*
do 
	# If it is a file.
	if [ -f ${FILE} ]
	then
		# Replaces variables in the files.
		NEW_FILE=$(envsubst < ${FILE})
		echo "${NEW_FILE}" > ${FILE}
		${DEBUG} && cat ${FILE}
	fi
done

# If the database file does not exist.
if [ ! -f ${CONFIG_DIR}/database/database.ini ] || ${RESET}
then

	# Creates it.
	mkdir -p ${CONFIG_DIR}/database
	touch ${CONFIG_DIR}/database/database.ini

fi

# Confiures the log.
PG_LOG=/var/log/postgresql/
mkdir -p ${PG_LOG}
chmod -R 755 ${PG_LOG}
chown -R postgres:postgres ${PG_LOG}

# Executes the init script.
echo "Starting pgbouncer..."
${DEBUG} && echo "exec pgbouncer ${QUIET:+-q} -u postgres ${CONFIG_DIR}/pgbouncer.ini"
exec pgbouncer ${QUIET:+-q} -u postgres ${CONFIG_DIR}/pgbouncer.ini

