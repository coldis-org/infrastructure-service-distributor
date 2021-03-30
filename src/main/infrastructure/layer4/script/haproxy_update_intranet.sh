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
${DEBUG} && echo "Running 'haproxy_update_intranet'"

CONF_FILES=/usr/local/etc/haproxy/service

# For each available net.
CONFIG_UPDATED=false
for NET in $(echo ${AVAILABLE_NETS} | sed "s/,/ /g")
do


	# For each configuration file.
	for CONF_FILE in ${CONF_FILES}/*
	do

		${DEBUG} && echo "Configuring ${NET} on ${CONF_FILE}"

		# For each host.
		for HOST_NUMBER in $(seq 0 49)
		do
	
			# Gets the old and new host IPs.
			OLD_ENTRY_CONFIG=$( cat ${CONF_FILE} | grep -A1 "${NET} ${HOST_NUMBER}\." | tail -1 | sed -e "s/^[ \t]*//g" )
			OLD_ENTRY_CONFIG=${OLD_ENTRY_CONFIG:="acl network_allowed src 127.0.0.255"}
			${DEBUG} && echo "Old entry config: ${OLD_ENTRY_CONFIG}"
			
			# If the Intranet IP is valid.
			ENTRY_NAME="site${HOST_NUMBER}.${NET}.${HOST_NAME}"
			NEW_ENTRY_IP=$( dig +short ${ENTRY_NAME} | tail -1 )
			${DEBUG} && echo "Entry name: ${ENTRY_NAME}"
			${DEBUG} && echo "New entry IP: ${NEW_ENTRY_IP}"
			if expr "${NEW_ENTRY_IP}" : '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}$' >/dev/null
			then
	
				# Gets the new host configuration.		
				NEW_ENTRY_CONFIG="acl network_allowed src ${NEW_ENTRY_IP}"
				NEW_ENTRY_CONFIG=${NEW_ENTRY_CONFIG:=${OLD_ENTRY_CONFIG}}
				${DEBUG} && echo "New entry config: ${NEW_ENTRY_CONFIG}"
	
				# If the IP has changed.
				if [ "${OLD_ENTRY_CONFIG}" != "${NEW_ENTRY_CONFIG}" ]
				then
				
					# If the old configuration is present.
					if (cat ${CONF_FILE} | grep "${OLD_ENTRY_CONFIG}")
					then
					
						# If the new configuration is not present.
						if !(cat ${CONF_FILE} | grep "${NEW_ENTRY_CONFIG}")
						then
						
							# Replaces them in the net file and sets the config as updated.
							${DEBUG} && echo "Updating entry ${HOST_NUMBER} for ${NET} in ${CONF_FILE} to: ${NEW_ENTRY_CONFIG}"
							sed -i "s/${OLD_ENTRY_CONFIG}/${NEW_ENTRY_CONFIG}/g" ${CONF_FILE}
							CONFIG_UPDATED=true
						
						# If the new configuration is present.
						else 
	
							# Logs it.						
							${DEBUG} && echo "New entry config ${HOST_NUMBER} is already present for ${NET} in ${CONF_FILE}"
							
						fi
						
					# If the old configuration is not present.
					else 
					
						# Logs it.						
						${DEBUG} && echo "Old entry config ${HOST_NUMBER} is not present for ${NET} in ${CONF_FILE}"
				
					fi
					
				# If the IP has not changed.
				else 
				
					# Logs it.						
						${DEBUG} && echo "Entry config ${HOST_NUMBER} has not changed for ${NET} in ${CONF_FILE}"

				fi
			
			# If the Intranet IP is not valid.
			else
				${DEBUG} && echo "Invalid entry IP: ${NEW_ENTRY_IP}"
			fi
	
		
		done
	
	done

done
	
# Reloads the configuration.
${DEBUG} && echo "CONFIG_UPDATED=${CONFIG_UPDATED}"
if ${CONFIG_UPDATED}
then
	kill -HUP 1
fi
	



