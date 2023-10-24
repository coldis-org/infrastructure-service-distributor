#!/bin/sh

# Default script behavior.
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
SKIP_RELOAD=false
SKIP_RELOAD_PARAM=""

# For each argument.
while :; do
	case ${1} in
		
		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
			;;
			
		# If actual reload should be done.
		--no-reload)
			SKIP_RELOAD=true
			SKIP_RELOAD_PARAM="--no-reload"
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
${DEBUG} && echo "Running 'nginx_update_intranet'"

CONFIG_UPDATED=false

# For each available net.
for NET in $(echo ${AVAILABLE_NETS} | sed "s/,/ /g")
do

	# For each host.
	for HOST_NUMBER in $(seq 0 199)
	do
	
		# Gets the old and new host IPs.
		CONF_FILE=/etc/nginx/conf.d/include.d/access-${NET}.conf
		OLD_HOST_CONFIG=$( cat ${CONF_FILE} | grep -A1 "Entry ${HOST_NUMBER}\." | grep "allow" | sed "s/^[ \t]*//g" )
		${DEBUG} && echo "OLD_HOST_CONFIG=${OLD_HOST_CONFIG}"
	
		# If the Intranet IP is valid.
		NET_IP=$( dig +short site${HOST_NUMBER}.${NET}.${HOST_NAME} | tail -1 )
		if expr "${NET_IP}" : '^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null; then
		
			# Gets the new host configuration.		
			NEW_HOST_CONFIG="allow ${NET_IP};"
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
	nginx_create_map_ip_list
	nginx_variables ${SKIP_RELOAD_PARAM}
	nginx_check_config ${SKIP_RELOAD_PARAM}
fi



