#!/bin/sh

# Default script behavior.
set -o errexit
#set -o pipefail

# Default paramterers.
DEBUG=false
PGBOUNCER_PARAMETERS=
PGBOUNCER_CERTS=/etc/ssl/certs
CERT_INFO="/C=${CERT_C}/ST=${CERT_ST}/L=${CERT_L}/O=${CERT_O}/OU=${CERT_OU}/CN=${CERT_CN}"
RESET=${RESET:=false} 

# For each argument.
while :; do
	case ${1} in
		
		# Debug argument.
		--debug)
			DEBUG=true
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

# Quotes an HBA value: wraps it in double quotes and doubles any double quote inside.
hba_quote() {
	printf '"%s"' "$(printf '%s' "${1}" | sed 's/"/""/g')"
}

# Appends an LDAP option when it has a value (an empty quoted value stops PgBouncer from
# reading the options after it).
ldap_option() {
	if [ -n "${2}" ]
	then
		LDAP_OPTIONS="${LDAP_OPTIONS} ${1}=$(hba_quote "${2}")"
	fi
}

# Generates the HBA file: the rejected users first, so they never reach LDAP, then LDAP
# search+bind for everyone else. Written here rather than through envsubst, which would
# blank the $username placeholder of the search filter.
if [ -z "${LDAP_URI}" ]
then
	echo "LDAP_URI is not set: no user could log in" >&2
	exit 1
fi
LDAP_OPTIONS=
ldap_option ldapserver "${LDAP_URI}"
ldap_option ldapport "${LDAP_PORT}"
ldap_option ldapbasedn "${LDAP_BASE_DN}"
ldap_option ldapbinddn "${LDAP_USER}"
ldap_option ldapbindpasswd "${LDAP_PASSWORD:-}"
ldap_option ldapsearchfilter "${LDAP_SEARCH_FILTER}"
REJECTED_USERS=$(echo "${REJECT_USERS}" | tr ',:' '  ')
{
	for REJECTED_USER in ${REJECTED_USERS}
	do
		echo "local all $(hba_quote "${REJECTED_USER}") reject"
		echo "host all $(hba_quote "${REJECTED_USER}") all reject"
	done
	echo "local all all ldap${LDAP_OPTIONS}"
	echo "host all all all ldap${LDAP_OPTIONS}"
} > "${AUTH_HBA_FILE}"
chmod 600 "${AUTH_HBA_FILE}"

# Replaces variables in the files.
CONF_FILE=${PGBOUNCER_CONFIG}/pgbouncer.ini
CONF=$(envsubst < ${CONF_FILE})
echo "${CONF}" > ${CONF_FILE}
CURRENT_PROCESS=$((CURRENT_PROCESS+1))

# Creates config files for each process.
CURRENT_PROCESS=0
while [ "${CURRENT_PROCESS}" -lt "${PROCESSES}" ]
do
	mkdir -p  /var/pgbouncer/socket/${CURRENT_PROCESS}
	cp ${PGBOUNCER_CONFIG}/pgbouncer.ini ${PGBOUNCER_CONFIG}/pgbouncer${CURRENT_PROCESS}.ini
	sed -i "s/CURRENT_PROCESS/${CURRENT_PROCESS}/g" ${PGBOUNCER_CONFIG}/pgbouncer${CURRENT_PROCESS}.ini
	CURRENT_PROCESS=$((CURRENT_PROCESS+1))
done

# Enforces permissions.
chown -R ${PGBOUNCER_USER}:${PGBOUNCER_USER} ${PGBOUNCER_CERTS} ${PGBOUNCER_LOGS} ${PGBOUNCER_SOCKET} ${PGBOUNCER_CONFIG} ${PGBOUNCER_BIN} && \
	chmod -R 755 ${PGBOUNCER_LOGS}

# Runs alternative processes.
CURRENT_PROCESS=1
while [ "${CURRENT_PROCESS}" -lt "${PROCESSES}" ]
do
	echo "Running extra process (${CURRENT_PROCESS})..."
	${PGBOUNCER_BIN}/pgbouncer ${QUIET:+-q} -u ${PGBOUNCER_USER} ${PGBOUNCER_CONFIG}/pgbouncer${CURRENT_PROCESS}.ini &
	CURRENT_PROCESS=$((CURRENT_PROCESS+1))
done

# Runs main process.
echo "Starting main process..."
${DEBUG} && echo "exec ${PGBOUNCER_BIN}/pgbouncer ${QUIET:+-q} -u ${PGBOUNCER_USER} ${PGBOUNCER_CONFIG}/pgbouncer.ini"
exec ${PGBOUNCER_BIN}/pgbouncer ${QUIET:+-q} -u ${PGBOUNCER_USER} ${PGBOUNCER_CONFIG}/pgbouncer0.ini

