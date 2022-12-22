#!/bin/sh

# Default script behavior.
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=true}
DEBUG_OPT=
VHOSTS_FOLDER=/etc/nginx/vhost.d
BRANCH_PREFIX="feat"

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
			printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
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

# Filter domains created by temporary services.
BRANCH_CERTS=$(grep -w "server_name" $VHOSTS_FOLDER/*http.conf | sed -e "s/.*server_name//g" | tr -d ';' | tr -d [:blank:] | grep "^${BRANCH_PREFIX}-")

${DEBUG} && echo "Running 'nginx_remove_branch_services_vhost'"

# Removing services branch certificates.
for CERT in $BRANCH_CERTS; do
	${DEBUG} && echo "Removing certificates $CERT"
	certbot delete --cert-name $CERT --non-interactive || true
	sleep 1
done

# Removing  temporary vhosts.
rm $VHOSTS_FOLDER/${BRANCH_PREFIX}-*.conf* -v || true
