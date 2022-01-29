#!/bin/sh

# Default script behavior.
set -o errexit
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
VHOSTS=/etc/nginx/vhost.d
CERTS=/etc/letsencrypt
VHOSTS_TMP=/tmp/nginx/${CONF_HOST_NAME}/vhost
CERTS_TMP=/tmp/nginx/${CONF_HOST_NAME}/cert

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

# Print arguments if on debug mode.
${DEBUG} && echo "Running 'nginx_sync_config'"


# If host config should be syncd.
if [ ! -z "${CONF_HOST_NAME}" ] && [ "$(hostname)" != "${CONF_HOST_NAME}" ]
then

	# Downloads data.
	rm -rf ${VHOSTS_TMP}/* ${CERTS_TMP}/*
	wget --recursive --no-parent -q -R "index.html*" -P ${VHOSTS_TMP}/../.. ${CONF_HOST_NAME}/vhost/
	wget --recursive --no-parent -q -R "index.html*" -P ${CERTS_TMP}/../.. ${CONF_HOST_NAME}/cert/
	
	if ! diff -q ${CERTS} ${CERTS_TMP}
	then
		rm -rf ${CERTS}/*
		mv ${CERTS_TMP}/* ${CERTS}/
		nginx -s reload
	fi

	if ! diff -q ${VHOSTS} ${VHOSTS_TMP}
	then
		rm -rf ${VHOSTS}/*
		mv ${VHOSTS_TMP}/* ${VHOSTS}/
		nginx -s reload
	fi

fi

