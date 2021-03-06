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
CONFIG_UPDATED=false

# For each host.
for HOST_NUMBER in $(seq 0 49)
do

	# Gets the old and new host IPs.
	OLD_HOST_CONFIG=$( cat ${CONF_FILE} | grep -A1 "Entry ${HOST_NUMBER}\." | grep "Allow" | sed "s/^[ \t]*//g" )
	${DEBUG} && echo "OLD_HOST_CONFIG=${OLD_HOST_CONFIG}"

	# If the Intranet IP is valid.
	INTRANET_IP=$( dig +short site${HOST_NUMBER}.${INTRANET_HOST_NAME} | tail -1 )
	if expr "${INTRANET_IP}" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null; then
	
		# Gets the new host configuration.		
		NEW_HOST_CONFIG="Allow from ${INTRANET_IP}"
		NEW_HOST_CONFIG=${NEW_HOST_CONFIG:=${OLD_HOST_CONFIG}}
		${DEBUG} && echo "NEW_HOST_CONFIG=${NEW_HOST_CONFIG}"
		
		# If the old configuration is present and the new configuration is not present.
		if (cat ${CONF_FILE} | grep "${OLD_HOST_CONFIG}" >/dev/null) && \
			! (cat ${CONF_FILE} | grep "${NEW_HOST_CONFIG}" >/dev/null)
		then
		
			# Replaces them in the intranet file.
			sed -i "s/${OLD_HOST_CONFIG}/${NEW_HOST_CONFIG}/g" ${CONF_FILE}
		
			# If the IP has changed.
			if [ "${OLD_HOST_CONFIG}" != "${NEW_HOST_CONFIG}" ]
			then
				# Sets that configuration has been updated.
				CONFIG_UPDATED=true
			fi
			
		# If the old configuration is not present.
		else 
			
			# No old config is present.
			${DEBUG} && echo "No old config present or new config already present."
			
		fi

	# If the Intranet IP is not valid.
	else
		${DEBUG} && echo "Invalid intranet IP: ${INTRANET_IP}"
	fi

done

# For each available net.
for NET in $(echo ${AVAILABLE_NETS} | sed "s/,/ /g")
do

	# For each host.
	for HOST_NUMBER in $(seq 0 49)
	do
	
		# Gets the old and new host IPs.
		CONF_FILE=/usr/local/apache2/conf/extra/httpd-access-${NET}.conf
		OLD_HOST_CONFIG=$( cat ${CONF_FILE} | grep -A1 "Entry ${HOST_NUMBER}\." | grep "Allow" | sed "s/^[ \t]*//g" )
		${DEBUG} && echo "OLD_HOST_CONFIG=${OLD_HOST_CONFIG}"
	
		# If the Intranet IP is valid.
		NET_IP=$( dig +short site${HOST_NUMBER}.${NET}.${HOST_NAME} | tail -1 )
		if expr "${NET_IP}" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null; then
		
			# Gets the new host configuration.		
			NEW_HOST_CONFIG="Allow from ${NET_IP}"
			NEW_HOST_CONFIG=${NEW_HOST_CONFIG:=${OLD_HOST_CONFIG}}
			${DEBUG} && echo "NEW_HOST_CONFIG=${NEW_HOST_CONFIG}"
			
			# If the old configuration is present and the new configuration is not present.
			if (cat ${CONF_FILE} | grep "${OLD_HOST_CONFIG}" >/dev/null) && \
				! (cat ${CONF_FILE} | grep "${NEW_HOST_CONFIG}" >/dev/null)
			then
			
				# Replaces them in the net file.
				sed -i "s/${OLD_HOST_CONFIG}/${NEW_HOST_CONFIG}/g" ${CONF_FILE}
			
				# If the IP has changed.
				if [ "${OLD_HOST_CONFIG}" != "${NEW_HOST_CONFIG}" ]
				then
					# Sets that configuration has been updated.
					CONFIG_UPDATED=true
				fi
				
			# If the old configuration is not present.
			else 
				
				# No old config is present.
				${DEBUG} && echo "No old config present or new config already present."
				
			fi
	
		# If the Intranet IP is not valid.
		else
			${DEBUG} && echo "Invalid net IP: ${NET_IP}"
		fi
	
	done

done

# Reloads the configuration.
${DEBUG} && echo "CONFIG_UPDATED=${CONFIG_UPDATED}"
if ${CONFIG_UPDATED}
then
	kill -USR1 1
fi



