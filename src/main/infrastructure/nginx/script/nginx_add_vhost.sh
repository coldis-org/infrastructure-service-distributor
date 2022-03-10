#!/bin/sh

# Default script behavior.
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

		-d|--directory)
			VHOSTS=${2}
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
mkdir -p $(dirname ${VHOST})
rm -f ${VHOST}.old ${VHOST}.tmp
while read VHOST_LINE
do
	echo "${VHOST_LINE}" >> ${VHOST}.tmp
done
${DEBUG} && cat ${VHOST}.tmp

# Updates the file only if it has changed.
touch ${VHOST}
nginx_variables --files ${VHOST}.tmp
if !(diff -s ${VHOST} ${VHOST}.tmp)
then
	# Changes the configuration.
	mv ${VHOST} ${VHOST}.old
	mv ${VHOST}.tmp ${VHOST}
	# If the config cannot be reloaded.
	${DEBUG} && echo "Reloading config"
	nginx_variables
	if nginx_check_config
	then
		rm -f ${VHOST}.old
	else 
		mv ${VHOST}.old ${VHOST} || true
		nginx_check_config
	fi
else 
	echo "Config file '${VHOST}' has not changed. Skipping."
fi
