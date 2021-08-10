#!/bin/sh

# Default script behavior.
set -o errexit
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
VHOSTS=/etc/nginx/vhost.d

# For each argument.
while :; do
	case ${1} in
		
		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
			;;
			
		# Virtual host name.
		-v|--vhost-name)
			VHOST_NAME=${2}
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

# Using unavaialble variables should fail the script.
set -o nounset

# Enables interruption signal handling.
trap - INT TERM

# Prepares virtual host.
VHOST=${VHOSTS}/${VHOST_NAME}.conf

# Print arguments if on debug mode.
${DEBUG} && echo "Running 'nginx_add_vhost'"
${DEBUG} && echo "VHOST_NAME=${VHOST_NAME}"
${DEBUG} && echo "VHOST=${VHOST}"

# Reads the input file line by line.
rm -f ${VHOST}.tmp
while read VHOST_LINE
do
	echo "${VHOST_LINE}" >> ${VHOST}.tmp
done
${DEBUG} && cat ${VHOST}.tmp

# Updates the file only if it has changed.
touch ${VHOST}
if !(diff -s ${VHOST} ${VHOST}.tmp)
then
	# Changes the configuration.
	rm ${VHOST}
	mv ${VHOST}.tmp ${VHOST}
	# If the config cannot be reloaded.
	${DEBUG} && echo "Reloading config"
	if ! nginx -s reload
	then
		# Erases the virtual host config.
		${DEBUG} && echo "Removing virtual host"
		rm -rf ${VHOST}
		nginx -s reload
		exit "Virtual host config invalid"
	fi
else 
	echo "Config file '${VHOST}' has not changed. Skipping."
fi


