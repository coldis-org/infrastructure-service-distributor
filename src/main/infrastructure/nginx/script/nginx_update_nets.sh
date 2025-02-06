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
set -o nounset

# Enables interruption signal handling.
trap - INT TERM

# Print arguments if on debug mode.
${DEBUG} && echo "Running 'nginx_update_nets'"

CONFIG_UPDATED=false

# Configures the local network.
if grep -q "{LOCALNET_IPS}" $CONF_FILE
then
	LOCALNET_CONF_FILE="${CONF_FILE_PATH}/access-localnet.conf"
    echo "$LOCALNET_IPS" | tr ',' '\n' | sed 's/^/allow /; s/$/;/' > ${LOCALNET_CONF_FILE}
else
    echo "" > ${LOCALNET_CONF_FILE}
fi

# For each available net.
for NET in $(echo ${AVAILABLE_NETS} | sed "s/,/ /g")
do

	# Creates the old and new files.
	CONF_FILE=${CONF_FILE_PATH}/access-${NET}.conf
    OLD_FILE=/tmp/access-${NET}.conf.old
    NEW_FILE=/tmp/access-${NET}.conf.new
    cp ${CONF_FILE} ${OLD_FILE}
    cp ${CONF_FILE_PATH}/access-anynet.conf.default ${NEW_FILE}

	# For each host.
	for HOST_NUMBER in $(seq 0 199)
	do

		# Initilize vars
		NEW_HOST_CONFIG=
		NET_IP=
		${DEBUG} && echo "Entry ${HOST_NUMBER}"

		# If the Intranet IP is valid.
		NET_IP=$( dig +short site${HOST_NUMBER}.${NET}.${HOST_NAME} | tail -1 )
		
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
	
	done

done

# Reloads the configuration if the file has been updated.
CONFIG_UPDATED=true
if diff -q ${OLD_FILE} ${NEW_FILE} > /dev/null; then
	CONFIG_UPDATED = false
fi
${DEBUG} && echo "CONFIG_UPDATED=${CONFIG_UPDATED}"
if ${CONFIG_UPDATED}
then
	cp -f ${NEW_FILE} ${CONF_FILE}
	rm -f ${OLD_FILE} ${NEW_FILE}
	nginx_variables ${SKIP_RELOAD_PARAM}
	nginx_check_config ${SKIP_RELOAD_PARAM}
fi


