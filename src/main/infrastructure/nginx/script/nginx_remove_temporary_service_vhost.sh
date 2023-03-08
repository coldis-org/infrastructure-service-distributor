#!/bin/sh

# Default script behavior.
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
VHOSTS_FOLDER=/etc/nginx/vhost.d
TEMP_PREFIX=${TEMP_PREFIX:="temp"}

# For each argument.
while :; do
	case ${1} in
		
		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
			;;
		# Temp prefix
		--temp-prefix)
			TEMP_PREFIX=${2}
			shift
			;;
		# Other option.
		?*)
			printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
			;;

		# No more options.
		*)
			break

	esac 
	shift
done

# Print if debug mode
${DEBUG} && echo "Running 'nginx_remove_temporary_service_vhost'"
${DEBUG} && echo "TEMP_PREFIX = $TEMP_PREFIX"

# Using unavaialble variables should fail the script.
set -o nounset

# Enables interruption signal handling.
trap - INT TERM

# Filter domains created by temporary services.
TEMP_CERTS=$(grep -w "server_name" $VHOSTS_FOLDER/*http.conf | sed -e "s/.*server_name//g" | tr -d ';' | tr -d [:blank:] | grep "^${TEMP_PREFIX}-")

${DEBUG} && echo "Running 'nginx_remove_branch_services_vhost'"

# Removing services temporary certificates.
for CERT in $TEMP_CERTS; do
	${DEBUG} && echo "Removing certificates $CERT"
	rm -rf /etc/letsencrypt/live/${CERT} -v 		|| true
	rm -rf /etc/letsencrypt/renewal/${CERT}.conf -v || true
	rm -rf /etc/letsencrypt/archive/${CERT} -v 		|| true
done

# Removing temporary vhosts.
rm $VHOSTS_FOLDER/${TEMP_PREFIX}-*.conf* -v || true
