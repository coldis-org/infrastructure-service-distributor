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
CONFIG_TMP=/tmp/nginx/${CONF_HOST_NAME}
VHOSTS_TMP=${CONFIG_TMP}/vhost
CERTS_TMP=${CONFIG_TMP}/cert
STREAM_TMP=${CONFIG_TMP}/stream

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
${DEBUG} && echo "CONF_HOST_NAME=${CONF_HOST_NAME}"
${DEBUG} && echo "hostname=$(hostname)"

# If host config should be syncd.
SYNC_DIFF=false
if [ ! -z "${CONF_HOST_NAME}" ] && [ "localhost" != "${CONF_HOST_NAME}" ] && [ "$(hostname)" != "${CONF_HOST_NAME}" ]
then

	${DEBUG} && echo "Synching config"
	# Downloads data.
	rm -rf ${VHOSTS_TMP}/* 
	rm -rf ${CERTS_TMP}/*
	rm -rf ${STREAM_TMP}/*
	
	wget --recursive --no-parent -q -R "index.html*" -P ${VHOSTS_TMP}/../.. ${CONF_HOST_NAME}/vhost/
	# Exit if config distributor is down.
	if [ $? -ne 0 ]; then
		${DEBUG} && echo "Failed to download folder"
		exit 0
	fi
	wget --recursive --no-parent -q -R "index.html*" -P ${CERTS_TMP}/../.. ${CONF_HOST_NAME}/cert/ --exclude-directories="cert/archive,cert/csr,cert/keys"
	wget --recursive --no-parent -q -R "index.html*" -P ${STREAM_TMP}/../.. ${CONF_HOST_NAME}/stream/

    # If there are differences, sync them.
    nginx_revert_config_errors
    nginx_revert_config_errors --pattern "${CONFIG_TMP}/*/*.conf.err"
	if ! diff -r ${CERTS} ${CERTS_TMP}
	then
		rm -rf ${CERTS}/*
		mv ${CERTS_TMP}/* ${CERTS}/
		SYNC_DIFF=true
	fi
	if ! diff -r ${VHOSTS} ${VHOSTS_TMP}
	then
		rm -rf ${VHOSTS}/*
		mv ${VHOSTS_TMP}/* ${VHOSTS}/
		SYNC_DIFF=true
	fi
	if ! diff -r ${STREAM} ${STREAM_TMP}
	then
		rm -rf ${STREAM}/*
		mv ${STREAM_TMP}/* ${STREAM}/
		SYNC_DIFF=true
	fi

fi

# Returns if the configuration was updated.
if ${SYNC_DIFF}
then
	echo "Changes detected when synching config. Should reload configuration."
    return 0
else 
	echo "No changes detected when synching config. Should not reload configuration."
    return 1
fi

