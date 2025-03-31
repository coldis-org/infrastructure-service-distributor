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
CONFIG_TMP=/tmp/nginx
OLD_CONFIG_TMP=${CONFIG_TMP}/old/${CONF_HOST_NAME}
OLD_VHOSTS_TMP=${OLD_CONFIG_TMP}/vhost
OLD_STREAM_TMP=${OLD_CONFIG_TMP}/stream
NEW_CONFIG_TMP=${CONFIG_TMP}/new/${CONF_HOST_NAME}
NEW_VHOSTS_TMP=${NEW_CONFIG_TMP}/vhost
NEW_CERTS_TMP=${NEW_CONFIG_TMP}/cert
NEW_STREAM_TMP=${NEW_CONFIG_TMP}/stream

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

if ! ${SKIP_ROUTINES}; then

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
		# Prepares folders.
		rm -rf ${OLD_VHOSTS_TMP} ${OLD_STREAM_TMP} \
				${NEW_VHOSTS_TMP} ${NEW_CERTS_TMP} ${NEW_STREAM_TMP}
		mkdir -p ${VHOSTS} ${CERTS} ${STREAM} \
				${OLD_VHOSTS_TMP} ${OLD_STREAM_TMP} \
				${NEW_VHOSTS_TMP} ${NEW_CERTS_TMP} ${NEW_STREAM_TMP}
		cp -rf ${VHOSTS}/* ${OLD_VHOSTS_TMP}
		cp -rf ${STREAM}/* ${OLD_STREAM_TMP}
		
		# Downloads the configuration.
		wget --recursive --no-parent -q -R "index.html*" -P ${NEW_CONFIG_TMP}/.. ${CONF_HOST_NAME}/vhost/
		# Exit if config distributor is down.
		if [ $? -ne 0 ]; then
			${DEBUG} && echo "Failed to download folder"
			exit 0
		fi
		wget --recursive --no-parent -q -R "index.html*" -P ${NEW_CONFIG_TMP}/.. ${CONF_HOST_NAME}/cert/ --exclude-directories="cert/archive,cert/csr,cert/keys"
		wget --recursive --no-parent -q -R "index.html*" -P ${NEW_CONFIG_TMP}/.. ${CONF_HOST_NAME}/stream/

		# If there are differences, sync them.
		nginx_revert_config_errors --pattern "${CONFIG_TMP}/*/*/*.conf.err"
		if ! diff -r ${CERTS} ${NEW_CERTS_TMP}
		then
			rm -rf ${CERTS}/*
			mv ${NEW_CERTS_TMP}/* ${CERTS}/
			SYNC_DIFF=true
		fi
		if ! diff -r ${OLD_VHOSTS_TMP} ${NEW_VHOSTS_TMP}
		then
			rm -rf ${VHOSTS}/*
			mv ${NEW_VHOSTS_TMP}/* ${VHOSTS}/
			SYNC_DIFF=true
		fi
		if ! diff -r ${OLD_STREAM_TMP} ${NEW_STREAM_TMP}
		then
			rm -rf ${STREAM}/*
			mv ${NEW_STREAM_TMP}/* ${STREAM}/
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
else
	${DEBUG} && echo "Skipping 'nginx_sync_config' due conditional"
fi