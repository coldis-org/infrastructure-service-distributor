#!/bin/sh

# Default script behavior.
set -o errexit
#set -o pipefail

# Debug is disabled by default.
DEBUG=false
DEBUG_OPT=

# Default parameters.
SERVICE_CONFIG_DIRECTORY=persistent-config/service

# For each argument.
while :; do
	case ${1} in
		
		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
			;;
			
		# Service config folder.
		-d|--service-config-directory)
			SERVICE_CONFIG_DIRECTORY=${2}
			shift
			;;

		# Service name.
		-n|--service-name)
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

# Reads the input file line by line.
SERVICE_CONFIG_FILE=
while read SERVICE_CONFIG_LINE
do
	case ${SERVICE_CONFIG_LINE} in
	
		# If the line starts with frontent.
		frontend:*)
			# Gets the frontend file.
			SERVICE_CONFIG_FILE=${SERVICE_CONFIG_DIRECTORY}/${SERVICE_CONFIG_LINE#frontend:*}.cfg
			if ! [ -f ${SERVICE_CONFIG_FILE} ]
			then
				touch ${SERVICE_CONFIG_FILE}
				echo "frontend ${SERVICE_CONFIG_LINE#frontend:*}" >> ${SERVICE_CONFIG_FILE}
				echo "	bind :${SERVICE_CONFIG_LINE#frontend:*}" >> ${SERVICE_CONFIG_FILE}
			fi
			SERVICE_CONFIG_LINE=
			# Removes old config.
			sed -i "/#<${SERVICE_NAME}>/,/#<\/${SERVICE_NAME}>/d" ${SERVICE_CONFIG_FILE}
			;;
			
		# If the line starts with backend.
		backend*)
			# Prepares config file is the service file.
			SERVICE_CONFIG_FILE=${SERVICE_CONFIG_DIRECTORY}/${SERVICE_NAME}.cfg
			rm -rf ${SERVICE_CONFIG_FILE}
			touch ${SERVICE_CONFIG_FILE}
			;;
			
	esac	
	
	# If there is a config file set and there is config information available.
	if [ "${SERVICE_CONFIG_FILE}" != "" ] && [ "${SERVICE_CONFIG_LINE}" != "" ]
	then
		# Writes the config to the file.
		echo "${SERVICE_CONFIG_LINE}" >> ${SERVICE_CONFIG_FILE}
	fi

done

# Using unavaialble variables should fail the script.
set -o nounset

# Enables interruption signal handling.
trap - INT TERM

# Print arguments if on debug mode.
${DEBUG} && echo "Running 'haproxy_create_service'"
${DEBUG} && echo "SERVICE_NAME=${SERVICE_NAME}"
${DEBUG} && echo "SERVICE_CONFIG=`cat ${SERVICE_CONFIG_DIRECTORY}/${SERVICE_NAME}.cfg`"

# Reloads the configuration.
kill -HUP 1
