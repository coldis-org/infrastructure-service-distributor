#!/bin/sh

# Default script behavior.
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
SKIP_RELOAD=false
SKIP_RELOAD_PARAM=""
VHOSTS=/etc/nginx/vhost.d
STREAM=/etc/nginx/stream.d
CERTS=/etc/letsencrypt
VHOSTS_TMP=/tmp/nginx/${CONF_HOST_NAME}/vhost
CERTS_TMP=/tmp/nginx/${CONF_HOST_NAME}/cert
STREAM_TMP=/tmp/nginx/${CONF_HOST_NAME}/stream

# For each argument.
while :; do
	case ${1} in
		
		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
			;;

		# If no reload should be performed.
		--no-reload)
			SKIP_RELOAD=true
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
${DEBUG} && echo "CONF_HOST_NAME=${CONF_HOST_NAME}"
${DEBUG} && echo "hostname=$(hostname)"

# If host config should be syncd.
if [ ! -z "${CONF_HOST_NAME}" ] && [ "localhost" != "${CONF_HOST_NAME}" ] && [ "$(hostname)" != "${CONF_HOST_NAME}" ]
then

	${DEBUG} && echo "Synching config"
	# Downloads data.
	rm -rf ${VHOSTS_TMP}/* 
	rm -rf ${CERTS_TMP}/*
	rm -rf ${STREAM_TMP}/*
	
	wget --recursive --no-parent -q -R "index.html*" -P ${VHOSTS_TMP}/../.. ${CONF_HOST_NAME}/vhost/
	# Exit if config distributor is down
	if [ $? -ne 0 ]; then
		${DEBUG} && echo "Failed to download folder"
		exit 0
	fi
	wget --recursive --no-parent -q -R "index.html*" -P ${CERTS_TMP}/../.. ${CONF_HOST_NAME}/cert/
	wget --recursive --no-parent -q -R "index.html*" -P ${STREAM_TMP}/../.. ${CONF_HOST_NAME}/stream/

	if ! diff -rq ${CERTS} ${CERTS_TMP}
	then
		rm -rf ${CERTS}/*
		mv ${CERTS_TMP}/* ${CERTS}/
		${SKIP_RELOAD} || nginx_check_config
	fi

	if ! diff -rq ${VHOSTS} ${VHOSTS_TMP}
	then
		rm -rf ${VHOSTS}/*
		mv ${VHOSTS_TMP}/* ${VHOSTS}/
		${SKIP_RELOAD} || nginx_check_config
	fi
	
	if ! diff -rq ${STREAM} ${STREAM_TMP}
	then
		rm -rf ${STREAM}/*
		mv ${STREAM_TMP}/* ${STREAM}/
		${SKIP_RELOAD} || nginx_check_config
	fi

fi

