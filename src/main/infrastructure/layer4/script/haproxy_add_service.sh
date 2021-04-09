#!/bin/sh

# Default script behavior.
set -o errexit
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=

# For each argument.
while :; do
	case ${1} in
		
		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
			;;
			
		# Virtual host name.
		-v|--service-name)
			SERVICE_NAME=${2}
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

# Prepares service.
SERVICE=${SERVICE_CONFIG_DIRECTORY}/${SERVICE_NAME}.cfg
rm -rf ${SERVICE}
touch ${SERVICE}

# Print arguments if on debug mode.
${DEBUG} && echo "Running 'haproxy_add_service'"
${DEBUG} && echo "SERVICE_NAME=${SERVICE_NAME}"
${DEBUG} && echo "SERVICE=${SERVICE}"

# Reads the input file line by line.
while read SERVICE_LINE
do
	echo "${SERVICE_LINE}" >> ${SERVICE}
done
${DEBUG} && cat ${SERVICE}

# If the config is not valid.
${DEBUG} && echo "Testing config"
if ! /usr/local/sbin/haproxy -c -f /usr/local/etc/haproxy -f /usr/local/etc/haproxy/service
then
	# Erases the service config.
	${DEBUG} && echo "Removing config"
	rm -f ${SERVICE}
	exit "Service config invalid"
else 
	# Reloads the configuration.
	kill -HUP 1
fi
