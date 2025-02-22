#!/bin/sh

# Default script behavior.
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
SKIP_RELOAD=false
SKIP_RELOAD_PARAM=""
CONF_FILE_PATH=/etc/nginx/conf.d
GENERAL_CONF_FILE_PATH=${CONF_FILE_PATH}/general.d
HTTP_CONF_FILE_PATH=${CONF_FILE_PATH}/http.d
INCLUDE_CONF_FILE_PATH=${CONF_FILE_PATH}/include.d

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
#set -o nounset
set +u

# Enables interruption signal handling.
trap - INT TERM

# Print arguments if on debug mode.
${DEBUG} && echo "Running 'nginx_update_nets'"

# Default parameters.
CONFIG_UPDATED=false

# Removes temporary files.
rm -f ${OLD_NET_CONF_FILE} ${NEW_NET_CONF_FILE} \
	${OLD_NET_HTTP_CONF_FILE} ${NEW_NET_HTTP_CONF_FILE} \
	${OLD_REQLIMITZONE_CONF_FILE} ${NEW_REQLIMITZONE_CONF_FILE} \
	${OLD_REQLIMIT_CONF_FILE} ${NEW_REQLIMIT_CONF_FILE} \
	${OLD_LOCALNET_CONF_FILE} ${NEW_LOCALNET_CONF_FILE} \
	${OLD_NETWORKS_CONF_FILE} ${NEW_NETWORKS_CONF_FILE} 

# Prepares network config.
NETWORKS_CONF_FILE=${GENERAL_CONF_FILE_PATH}/networks.conf
if [ ! -f ${NETWORKS_CONF_FILE} ]
then
    touch ${NETWORKS_CONF_FILE}
fi
OLD_NETWORKS_CONF_FILE=/tmp/networks.conf.old
NEW_NETWORKS_CONF_FILE=/tmp/networks.conf.new
cp -f ${NETWORKS_CONF_FILE} ${OLD_NETWORKS_CONF_FILE}
cp -f ${GENERAL_CONF_FILE_PATH}/networks.conf.default ${NEW_NETWORKS_CONF_FILE}

# Prepares reqlimitzone config.
REQLIMITZONE_CONF_FILE=${HTTP_CONF_FILE_PATH}/reqlimitzone.conf
if [ ! -f ${REQLIMITZONE_CONF_FILE} ]
then
    touch ${REQLIMITZONE_CONF_FILE}
fi
OLD_REQLIMITZONE_CONF_FILE=/tmp/reqlimitzone.conf.old
NEW_REQLIMITZONE_CONF_FILE=/tmp/reqlimitzone.conf.new
cp -f ${REQLIMITZONE_CONF_FILE} ${OLD_REQLIMITZONE_CONF_FILE}
cp -f ${HTTP_CONF_FILE_PATH}/reqlimitzone.conf.default ${NEW_REQLIMITZONE_CONF_FILE}

# Prepares reqlimit config.
REQLIMIT_CONF_FILE=${INCLUDE_CONF_FILE_PATH}/reqlimit.conf
if [ ! -f ${REQLIMIT_CONF_FILE} ]
then
    touch ${REQLIMIT_CONF_FILE}
fi
OLD_REQLIMIT_CONF_FILE=/tmp/reqlimit.conf.old
NEW_REQLIMIT_CONF_FILE=/tmp/reqlimit.conf.new
cp -f ${REQLIMIT_CONF_FILE} ${OLD_REQLIMIT_CONF_FILE}
cp -f ${INCLUDE_CONF_FILE_PATH}/reqlimit.conf.default ${NEW_REQLIMIT_CONF_FILE}

# Configures the local network.
if [ ! -z "${LOCALNET_IPS}" ]
then

	# Prepares the local network config files.
	LOCALNET_CONF_FILE="${INCLUDE_CONF_FILE_PATH}/access-localnet.conf"
	if [ ! -f ${LOCALNET_CONF_FILE} ]
	then
	    touch ${LOCALNET_CONF_FILE}
	fi
	OLD_LOCALNET_CONF_FILE=/tmp/access-localnet.conf.old
	NEW_LOCALNET_CONF_FILE=/tmp/access-localnet.conf.new	
	cp -f ${LOCALNET_CONF_FILE} ${OLD_LOCALNET_CONF_FILE}
	echo "" > ${NEW_LOCALNET_CONF_FILE}
	
	# For each local network IP.
	for LOCALNET_IP in $(echo ${LOCALNET_IPS} | sed "s/,/ /g")
	do

		# Adds the local network IP to the permitted list.
	    echo "allow ${LOCALNET_IP};" >> ${NEW_LOCALNET_CONF_FILE}

		# Adds the local network to exception list in reqlimit config.
		sed -ie "s|\(# Network definitions\.\)|\1\n    ${LOCALNET_IP}\t\t\t\"localnet\"\;|" ${NEW_NETWORKS_CONF_FILE}

	done
	
	# Adds the local network to exception list in reqlimit config.
	sed -ie "s|\(# Removes IPs from other networks\.\)|\1\n    \"localnet\"\t\t\t\"\";|" ${NEW_NETWORKS_CONF_FILE}
	sed -ie "s|\(# Removes IPs from local network\.\)|\1\n    \"localnet\"\t\t\t\"\";|" ${NEW_NETWORKS_CONF_FILE}

fi

# For each available net.
for NET_PAIR in $(echo ${AVAILABLE_NETS} | sed "s/,/ /g")
do

	# Gets the network and its subdomain.
	NET=$(echo "${NET_PAIR}" | sed -e "s/\([^\/]*\).*/\1/")
	NET_SUBDOMAIN=$(echo "${NET_PAIR}" | sed -e "s/^[^\/]*[\/$]\(.*\)$/\1/")

	# Adds the network to the network options.
	sed -ie "s|\(# Removes IPs from other networks\.\)|\1\n    \"${NET}\"\t\t\t\"\";|g" ${NEW_NETWORKS_CONF_FILE}

	# Adds the network reqlimit key.
    sed -ie "s|\(# Defines request limit zones for specific networks\.\)|\1\nlimit_req_zone \$localnet_ip_key zone=one:10m rate=1r/s|" ${NEW_REQLIMITZONE_CONF_FILE} 

	# Creates a key for the network IP addresses
	if ! ( cat ${NEW_NETWORKS_CONF_FILE} | grep -q "map \$network \$remote_addr_${NET} {" )
	then
	    echo "
	# Address for ${NET} variable.
	map \$network \$remote_addr_${NET} {
		"${NET}"				\$binary_remote_addr;
	    default			\"\";
	}
	" >> ${NEW_NETWORKS_CONF_FILE}
	fi

	# Creates the reqlimit zone for the network.
    REQLIMIT_RATE_VAR=$(echo "${NET}_REQLIMIT" | tr '[:lower:]' '[:upper:]')
	eval "REQLIMIT_RATE=\${${REQLIMIT_RATE_VAR}:=}"
	if [ -z "${REQLIMIT_RATE}" ]
    then
        REQLIMIT_RATE="${DEFAULT_TRUSTED_REQLIMIT_RATIO}"
    fi
	echo "
# Defines request limit zones for ${NET} network.
limit_req_zone \$remote_addr_${NET} zone=${NET}_http_limit:${REQLIMIT_ZONE_SIZE} rate=${REQLIMIT_RATE};
" >> ${NEW_REQLIMITZONE_CONF_FILE}
	
	# Adds the request limit for the network.
	sed -ie "s|\(# Configures request limits\.\)|\1\nlimit_req zone=${NET}_http_limit nodelay;|" ${NEW_REQLIMITZONE_CONF_FILE}

	# Creates the access files.
	NET_CONF_FILE=${INCLUDE_CONF_FILE_PATH}/access-${NET}.conf
	NET_HTTP_CONF_FILE=${INCLUDE_CONF_FILE_PATH}/access-${NET}-http.conf
	if [ ! -f ${NET_CONF_FILE} ]
	then
	    touch ${NET_CONF_FILE}
    fi
	if [ ! -f ${NET_HTTP_CONF_FILE} ]
	then
	    touch ${NET_HTTP_CONF_FILE}
    fi
    OLD_NET_CONF_FILE=/tmp/access-${NET}.conf.old
    NEW_NET_CONF_FILE=/tmp/access-${NET}.conf.new
    cp -f ${NET_CONF_FILE} ${OLD_NET_CONF_FILE}
    cp -f ${INCLUDE_CONF_FILE_PATH}/access-anynet.conf.default ${NEW_NET_CONF_FILE}
    OLD_NET_HTTP_CONF_FILE=/tmp/access-${NET}-http.conf.old
    NEW_NET_HTTP_CONF_FILE=/tmp/access-${NET}-http.conf.new
    cp -f ${NET_HTTP_CONF_FILE} ${OLD_NET_HTTP_CONF_FILE}
    
    # HTTP conf file imcludes the TCP config.
    echo "

# Includes the TCP configuration.
include ${NET_CONF_FILE};
    
" > ${NEW_NET_HTTP_CONF_FILE}
    
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
set \$${NET}_header_check \"\";
if (\$http_${NET_HEADER_NAME} ${NET_HEADER_VALUE_CHECK} \"${NET_HEADER_VALUE}\") {
	set \$${NET}_header_check \"\${network}-not-checked\";
}
if (\$${NET}_header_check = \"${NET}-not-checked\") {
	return 403;
}
" >> ${NEW_NET_HTTP_CONF_FILE}
    fi

	# For each host.
	for HOST_NUMBER in $(seq 0 199)
	do

		# Initilize svars.
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
				sed -i "/# Entry ${HOST_NUMBER}\.$/!b;n;c ${NEW_HOST_CONFIG}" ${NEW_NET_CONF_FILE}
				
				# Adds the ip to the network list.
				if ! ( cat ${NEW_NETWORKS_CONF_FILE} | grep -q "${NET_IP}" )
				then
					sed -ie "s|\(# Network definitions\.\)|\1\n    ${NET_IP}\t\t\t\"${NET}\"\;|" ${NEW_NETWORKS_CONF_FILE}
				fi
				
			# If the Intranet IP is not valid.
			else
				${DEBUG} && echo "Invalid net IP: ${NET_IP}"
			fi
		
		fi
	
	done
	
	# Reloads the configuration if the file has been updated.
	if  ( ! diff "${OLD_NET_CONF_FILE}" "${NEW_NET_CONF_FILE}" ) || \
        ( ! diff "${OLD_NET_HTTP_CONF_FILE}" "${NEW_NET_HTTP_CONF_FILE}" )
    then
        CONFIG_UPDATED=true
    fi
    if ${CONFIG_UPDATED}
	then
		cp -f ${NEW_NET_CONF_FILE} ${NET_CONF_FILE}
		cp -f ${NEW_NET_HTTP_CONF_FILE} ${NET_HTTP_CONF_FILE}
	fi
	rm -f ${OLD_NET_CONF_FILE} ${NEW_NET_CONF_FILE} \
        ${OLD_NET_HTTP_CONF_FILE} ${NEW_NET_HTTP_CONF_FILE}


done

# Reloads the configuration if the file has been updated.
if  ( ! diff "${OLD_REQLIMITZONE_CONF_FILE}" "${NEW_REQLIMITZONE_CONF_FILE}" ) || \
	( ! diff "${OLD_LOCALNET_CONF_FILE}" "${NEW_LOCALNET_CONF_FILE}" ) || \
	( ! diff "${OLD_NETWORKS_CONF_FILE}" "${NEW_NETWORKS_CONF_FILE}" ) || \
	( ! diff "${OLD_REQLIMIT_CONF_FILE}" "${NEW_REQLIMIT_CONF_FILE}" )
then
    CONFIG_UPDATED=true
fi
${DEBUG} && echo "CONFIG_UPDATED=${CONFIG_UPDATED}"
if ${CONFIG_UPDATED}
then
	cp -f ${NEW_LOCALNET_CONF_FILE} ${LOCALNET_CONF_FILE}
	cp -f ${NEW_REQLIMITZONE_CONF_FILE} ${REQLIMITZONE_CONF_FILE}
	cp -f ${NEW_REQLIMIT_CONF_FILE} ${REQLIMIT_CONF_FILE}
	cp -f ${NEW_NETWORKS_CONF_FILE} ${NETWORKS_CONF_FILE}
fi

# Removes temporary files.
rm -f ${OLD_REQLIMITZONE_CONF_FILE} ${NEW_REQLIMITZONE_CONF_FILE} \
	${OLD_REQLIMIT_CONF_FILE} ${NEW_REQLIMIT_CONF_FILE} \
	${OLD_LOCALNET_CONF_FILE} ${NEW_LOCALNET_CONF_FILE} \
	${OLD_NETWORKS_CONF_FILE} ${NEW_NETWORKS_CONF_FILE} 

# Returns if the configuration was updated.
if ${CONFIG_UPDATED}
then
	echo "Changes detected in network files. Should reload configuration."
	return 0
else 
	echo "No changes detected in network files. Should not reload configuration."
	return 1
fi

