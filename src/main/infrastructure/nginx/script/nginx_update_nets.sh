#!/bin/sh

# Default script behavior.
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
SKIP_RELOAD=false
SKIP_RELOAD_PARAM=""
CONF_FILE_PATH=/etc/nginx/conf.d/include.d

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
#set -o nounset
set +u

# Enables interruption signal handling.
trap - INT TERM

# Print arguments if on debug mode.
${DEBUG} && echo "Running 'nginx_update_nets'"

# Configures the local network.
if [ ! -z "${LOCALNET_IPS}" ]
then
	LOCALNET_CONF_FILE="${CONF_FILE_PATH}/access-localnet.conf"
    echo "$LOCALNET_IPS" | tr ',' '\n' | sed 's/^/allow /; s/$/;/' > ${LOCALNET_CONF_FILE}
else
    echo "" > ${LOCALNET_CONF_FILE}
fi

# For each available net.
for NET_PAIR in $(echo ${AVAILABLE_NETS} | sed "s/,/ /g")
do

	# Gets the network and its subdomain.
	NET=$(echo "${NET_PAIR}" | sed -e "s/\([^\/]*\).*/\1/")
	NET_SUBDOMAIN=$(echo "${NET_PAIR}" | sed -e "s/^[^\/]*[\/$]\(.*\)$/\1/")

	# Creates the old and new files.
	CONF_FILE=${CONF_FILE_PATH}/access-${NET}.conf
	HTTP_CONF_FILE=${CONF_FILE_PATH}/access-${NET}-http.conf
	if [ ! -f ${CONF_FILE} ]
	then
	    touch ${CONF_FILE}
    fi
    OLD_FILE=/tmp/access-${NET}.conf.old
    NEW_FILE=/tmp/access-${NET}.conf.new
    cp -f ${CONF_FILE} ${OLD_FILE}
    cp -f ${CONF_FILE_PATH}/access-anynet.conf.default ${NEW_FILE}
    OLD_HTTP_FILE=/tmp/access-${NET}-http.conf.old
    NEW_HTTP_FILE=/tmp/access-${NET}-http.conf.new
    cp -f ${HTTP_CONF_FILE} ${OLD_HTTP_FILE}
    
    # HTTP conf file imcludes the TCP config.
    echo "

# Includes the TCP configuration.
include ${CONF_FILE};
    
" > ${NEW_HTTP_FILE}
    
    # Adds header validation if variables are available.
    NET_HEADER_VAR=$(echo "${NET}_HEADER" | tr '[:lower:]' '[:upper:]')
	eval "NET_HEADER_PAIR=\${${NET_HEADER_VAR}}"
	NET_HEADER_NAME=$(echo "${NET_HEADER_PAIR}" | sed -e "s/\([^=]*\).*/\1/")
	NET_HEADER_VALUE=$(echo "${NET_HEADER_PAIR}" | sed -e "s/[^=]*[=$]*//")
    if [ ! -z "${NET_HEADER_NAME}" ]
    then
    	NET_HEADER_VALUE_CHECK="!="
    	if [ -z "${NET_HEADER_VALUE}" ]
    	then
    		NET_HEADER_VALUE_CHECK="="
    	fi
    
    	echo "

# Validates the header.
if (\$http_${NET_HEADER_NAME} ${NET_HEADER_VALUE_CHECK} \"${NET_HEADER_VALUE}\") {
    return 403;
}

" >> ${NEW_HTTP_FILE}
    fi

	# For each host.
	for HOST_NUMBER in $(seq 0 199)
	do

		# Initilize vars
		NEW_HOST_CONFIG=
		NET_IP=
		${DEBUG} && echo "Entry ${HOST_NUMBER}"

        # If the host name is valid.
        if [ ! -z "${HOST_NAME:=}" ]
        then
        
			# If the Intranet IP is valid.
			NET_IP=$( dig +short site${HOST_NUMBER}.${NET_SUBDOMAIN}.${HOST_NAME} | tail -1 )
			
		    # If the IP is valid.
			if expr "${NET_IP}" : '^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null; then
			
				# Replaces them in the net file. Get the next line after entry from file.
				NEW_HOST_CONFIG="allow ${NET_IP};"
				${DEBUG} && echo "NEW_HOST_CONFIG=${NEW_HOST_CONFIG}"
				sed -i "/# Entry ${HOST_NUMBER}\.$/!b;n;c ${NEW_HOST_CONFIG}" ${CONF_FILE}
		
			# If the Intranet IP is not valid.
			else
				${DEBUG} && echo "Invalid net IP: ${NET_IP}"
			fi
		
		fi
	
	done

done

# Reloads the configuration if the file has been updated.
CONFIG_UPDATED=true
if diff -q "${OLD_FILE}" "${NEW_FILE}" > /dev/null && diff -q "${OLD_HTTP_FILE}" "${NEW_HTTP_FILE}" > /dev/null
then
    CONFIG_UPDATED=false
fi
${DEBUG} && echo "CONFIG_UPDATED=${CONFIG_UPDATED}"
if ${CONFIG_UPDATED}
then
	cp -f ${NEW_FILE} ${CONF_FILE}
	cp -f ${NEW_HTTP_FILE} ${HTTP_CONF_FILE}
	rm -f ${OLD_FILE} ${NEW_FILE} ${OLD_HTTP_FILE} ${NEW_HTTP_FILE}
	nginx_variables ${SKIP_RELOAD_PARAM}
	nginx_check_config ${SKIP_RELOAD_PARAM}
fi


