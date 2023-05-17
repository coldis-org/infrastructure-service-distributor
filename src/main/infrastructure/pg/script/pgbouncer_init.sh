#!/bin/sh

# Default script behavior.
set -o errexit
#set -o pipefail

# Default paramterers.
DEBUG=false
DEBUG_OPT=
PGBOUNCER_PARAMETERS=
PGBOUNCER_CERTS=/etc/ssl/certs
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
openssl req -new -x509 -nodes -text -out ${PGBOUNCER_CERTS}/server.crt \
	-keyout ${PGBOUNCER_CERTS}/server.key -subj "${CERT_INFO}"
chmod og-rwx ${PGBOUNCER_CERTS}/server.key

# If the database file does not exist.
if [ ! -f ${PGBOUNCER_CONFIG}/database/database.ini ] || ${RESET}
then

	# Creates it.
	mkdir -p ${PGBOUNCER_CONFIG}/database
	touch ${PGBOUNCER_CONFIG}/database/database.ini

fi

# Replaces variables in the files.
LDAP_CONF_FILE=/etc/pam_ldap.conf
LDAP_CONF=$(envsubst < ${LDAP_CONF_FILE})
echo "${LDAP_CONF}" > ${LDAP_CONF_FILE}
CONF_FILE=${PGBOUNCER_CONFIG}/pgbouncer.ini
CONF=$(envsubst < ${CONF_FILE})
echo "${CONF}" > ${CONF_FILE}

# Executes the init script.
echo "Starting pgbouncer..."
${DEBUG} && echo "exec ${PGBOUNCER_BIN}/pgbouncer ${QUIET:+-q} -u ${PGBOUNCER_USER} ${PGBOUNCER_CONFIG}/pgbouncer.ini"
su postgres
exec ${PGBOUNCER_BIN}/pgbouncer ${QUIET:+-q} -u ${PGBOUNCER_USER} ${PGBOUNCER_CONFIG}/pgbouncer.ini

