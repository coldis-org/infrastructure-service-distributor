#!/bin/sh

# Default script behavior.
set -o errexit
#set -o pipefail

# Default parameters.
DEBUG=false
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

# Print arguments if on debug mode.
${DEBUG} && echo "Running 'apache_add_vhost'"
${DEBUG} && echo "VHOST_NAME=${VHOST_NAME}"

# Prepares virtual host.
VHOST=${VHOSTS}/${VHOST_NAME}.conf
rm -rf ${VHOST}
touch ${VHOST}
# Reads the input file line by line.
while read VHOST_LINE
do
	
	echo "${VHOST_LINE}" >> ${VHOST}

done

# Reloads the configuration.
/etc/init.d/apache2 reload
