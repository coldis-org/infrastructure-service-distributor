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
${DEBUG} && echo "Running 'apache_update_intranet'"

CONF_FILE=/usr/local/apache2/conf/extra/httpd-intranet.conf

# For each host.
CONFIG_UPDATED=false
for HOST_NUMBER in $(seq 0 4)
do

	# Gets the old and new host IPs.
	OLD_HOST_CONFIG=$( cat ${CONF_FILE} | grep -A1 "Intranet ${HOST_NUMBER}" | grep "Allow" | sed "s/^[ \t]*//g" )
	NEW_HOST_CONFIG="Allow from $( dig +short site${HOST_NUMBER}.${INTRANET_HOST_NAME} | tail -1 )"
	NEW_HOST_CONFIG=${NEW_HOST_CONFIG:=${OLD_HOST_CONFIG}}
	${DEBUG} && echo "OLD_HOST_CONFIG=${OLD_HOST_CONFIG}"
	${DEBUG} && echo "NEW_HOST_CONFIG=${NEW_HOST_CONFIG}"
	
	# Replaces them in the intranet file.
	sed -i "s/${OLD_HOST_CONFIG}/${NEW_HOST_CONFIG}/g" ${CONF_FILE}
	
	# If the IP has changed.
	if [ "${OLD_HOST_CONFIG}" != "${NEW_HOST_CONFIG}" ]
	then
		# Sets that configuration has been updated.
		CONFIG_UPDATED=true
	fi

done

# Reloads the configuration.
${DEBUG} && echo "CONFIG_UPDATED=${CONFIG_UPDATED}"
if ${CONFIG_UPDATED}
then
	kill -USR1 1
fi



