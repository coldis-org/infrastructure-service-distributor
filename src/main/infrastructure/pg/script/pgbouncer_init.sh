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

# Escapes an LDAP filter value (RFC 4515).
ldap_escape() {
	printf '%s' "${1}" | sed 's/\\/\\5c/g; s/\*/\\2a/g; s/(/\\28/g; s/)/\\29/g'
}

# Refuses a value with a line break: it would end its HBA line and start a rule of its own.
NEWLINE='
'
CARRIAGE_RETURN=$(printf '\r')
single_line() {
	case "${2}" in
		*"${NEWLINE}"*|*"${CARRIAGE_RETURN}"*)
			echo "${1} must be a single line" >&2
			exit 1
			;;
	esac
}

# Generates the HBA file: the rejected users first, so they never reach LDAP, then LDAP
# search+bind for everyone else. The rejected users are also left out of the search, on
# every attribute the filter matches $username with, so another spelling (LDAP matches
# case-insensitively) finds no entry either. Written here rather than through envsubst,
# which would blank the $username placeholder of the search filter.
single_line LDAP_URI "${LDAP_URI}"
single_line LDAP_PORT "${LDAP_PORT}"
single_line LDAP_BASE_DN "${LDAP_BASE_DN}"
single_line LDAP_USER "${LDAP_USER}"
single_line LDAP_PASSWORD "${LDAP_PASSWORD:-}"
single_line LDAP_SEARCH_FILTER "${LDAP_SEARCH_FILTER}"
single_line REJECT_USERS "${REJECT_USERS}"
single_line LDAP_SCHEME "${LDAP_SCHEME:-}"
single_line LDAP_TLS "${LDAP_TLS:-}"
case "${LDAP_SCHEME:-}" in
	""|ldap|ldaps)
		;;
	*)
		echo "LDAP_SCHEME must be ldap or ldaps: ${LDAP_SCHEME}" >&2
		exit 1
		;;
esac
case "${LDAP_TLS:-}" in
	""|0|1)
		;;
	*)
		echo "LDAP_TLS must be 0 or 1: ${LDAP_TLS}" >&2
		exit 1
		;;
esac
# Two combinations that boot but leave no way to log in.
if [ "${LDAP_SCHEME:-}" = ldaps ] && [ "${LDAP_TLS:-}" = 1 ]
then
	echo "LDAP_SCHEME=ldaps is already TLS: leave LDAP_TLS (StartTLS) unset" >&2
	exit 1
fi
if [ "${LDAP_SCHEME:-}" = ldaps ] && [ "${LDAP_PORT}" = 389 ]
then
	echo "LDAP_SCHEME=ldaps needs the ldaps port (usually LDAP_PORT=636), not 389" >&2
	exit 1
fi
# libldap reads LDAPTLS_REQCERT from the environment; these values skip the certificate check.
case "${LDAPTLS_REQCERT:-}" in
	""|demand|hard)
		;;
	*)
		echo "LDAPTLS_REQCERT=${LDAPTLS_REQCERT} would turn off the LDAP server certificate check" >&2
		exit 1
		;;
esac
# The environment wins over every libldap config file (ldap.conf, ldaprc), so set it here.
export LDAPTLS_REQCERT="${LDAPTLS_REQCERT:-demand}"
if [ -z "${LDAP_URI}" ] || [ -z "${LDAP_BASE_DN}" ]
then
	echo "LDAP_URI and LDAP_BASE_DN must be set, or no user could log in" >&2
	exit 1
fi
case "${LDAP_URI}" in
	*://*)
		echo "LDAP_URI is the LDAP host name, not a URL: ${LDAP_URI}" >&2
		exit 1
		;;
esac
REJECTED_USERS=$(printf '%s' "${REJECT_USERS}" | tr ',:' '  ')
# PgBouncer's own default when no filter is given.
SEARCH_FILTER=${LDAP_SEARCH_FILTER:-(uid=\$username)}
case "${SEARCH_FILTER}" in
	*'$username'*)
		;;
	*)
		echo "LDAP_SEARCH_FILTER must contain \$username: ${SEARCH_FILTER}" >&2
		exit 1
		;;
esac
# libldap takes a bare item (cn=$username), but it cannot be ANDed without parentheses.
case "${SEARCH_FILTER}" in
	"("*)
		;;
	*)
		SEARCH_FILTER="(${SEARCH_FILTER})"
		;;
esac
if [ -n "${REJECTED_USERS}" ]
then
	LOGIN_ATTRIBUTES=$(printf '%s' "${SEARCH_FILTER}" | grep -o '([A-Za-z][A-Za-z0-9.;-]*=\$username)' | sed 's/^(//; s/=.*//' | sort -u)
	if [ -z "${LOGIN_ATTRIBUTES}" ]
	then
		echo "REJECT_USERS needs a filter that matches \$username as (attribute=\$username): ${SEARCH_FILTER}" >&2
		exit 1
	fi
	SEARCH_FILTER="(&${SEARCH_FILTER}"
	for REJECTED_USER in ${REJECTED_USERS}
	do
		for LOGIN_ATTRIBUTE in ${LOGIN_ATTRIBUTES}
		do
			SEARCH_FILTER="${SEARCH_FILTER}(!(${LOGIN_ATTRIBUTE}=$(ldap_escape "${REJECTED_USER}")))"
		done
	done
	SEARCH_FILTER="${SEARCH_FILTER})"
fi
# PgBouncer expands $username into a 256-byte buffer and silently cuts the rest, which
# breaks the filter. It must fit with a 63-byte user name (PostgreSQL's longest role name).
PLACEHOLDERS=$(printf '%s' "${SEARCH_FILTER}" | grep -o '\$username' | wc -l)
# PgBouncer counts bytes; ${#var} would count characters.
EXPANDED_LENGTH=$(( $(printf '%s' "${SEARCH_FILTER}" | wc -c) + PLACEHOLDERS * (63 - 9) ))
if [ "${EXPANDED_LENGTH}" -ge 256 ]
then
	echo "The LDAP search filter reaches ${EXPANDED_LENGTH} bytes with a 63-byte user name, PgBouncer takes 255 (fewer REJECT_USERS?)" >&2
	exit 1
fi
LDAP_OPTIONS=
ldap_option ldapscheme "${LDAP_SCHEME:-}"
if [ "${LDAP_TLS:-}" = 1 ]
then
	ldap_option ldaptls 1
fi
ldap_option ldapserver "${LDAP_URI}"
ldap_option ldapport "${LDAP_PORT}"
ldap_option ldapbasedn "${LDAP_BASE_DN}"
ldap_option ldapbinddn "${LDAP_USER}"
ldap_option ldapbindpasswd "${LDAP_PASSWORD:-}"
ldap_option ldapsearchfilter "${SEARCH_FILTER}"
# PgBouncer silently cuts the options to MAX_LDAP_CONFIG - 1 (1023) bytes and parses the rest:
# a cut filter fails every login, but a dropped one falls back to (uid=$username) without the
# BLOCKED and REJECT_USERS clauses. This check is what keeps that from happening.
LDAP_OPTIONS_BYTES=$(( $(printf '%s' "${LDAP_OPTIONS}" | wc -c) ))
if [ "${LDAP_OPTIONS_BYTES}" -ge 1024 ]
then
	echo "The LDAP options are ${LDAP_OPTIONS_BYTES} bytes, too long for PgBouncer (fewer REJECT_USERS?)" >&2
	exit 1
fi
# The file holds the bind password: written to a new file under umask 077 (an existing one
# would keep its mode while being rewritten), then moved into place.
HBA_TEMP="${AUTH_HBA_FILE}.new"
rm -f "${HBA_TEMP}"
(
	umask 077
	{
		for REJECTED_USER in ${REJECTED_USERS}
		do
			printf '%s\n' "local all $(hba_quote "${REJECTED_USER}") reject"
			printf '%s\n' "host all $(hba_quote "${REJECTED_USER}") all reject"
		done
		printf '%s\n' "local all all ldap${LDAP_OPTIONS}"
		printf '%s\n' "host all all all ldap${LDAP_OPTIONS}"
	} > "${HBA_TEMP}"
)
chmod 600 "${HBA_TEMP}"
chown "${PGBOUNCER_USER}:${PGBOUNCER_USER}" "${HBA_TEMP}"
mv -f "${HBA_TEMP}" "${AUTH_HBA_FILE}"
# The HBA file has it now; the PgBouncer processes need not inherit it.
unset LDAP_PASSWORD

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

