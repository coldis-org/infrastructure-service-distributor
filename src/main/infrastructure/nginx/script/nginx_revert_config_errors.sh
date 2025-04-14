#!/bin/sh

# Default script behavior.
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
conf_folder=/etc/nginx/
error_files_name_pattern=*.conf*.err

# For each argument.
while :; do
	case ${1} in
		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
			;;
		# Error files pattern.
		--pattern)
			error_files_name_pattern=${2}
			shift
			;;
		# No more options.
		*)
			break

	esac 
	shift
done

# Enables interruption signal handling.
trap - INT TERM

# Print arguments if on debug mode.
${DEBUG} && echo "Running 'nginx_revert_config_errors'"

# Error files.
ERROR_FILES=$( find ${conf_folder} -type f -name "${error_files_name_pattern}" )
for ERROR_FILE in ${ERROR_FILES}
do
	if [ -f "${ERROR_FILE}" ]
	then
		# If the original file exists, removes the error file.
		ORIGINAL_FILE=$(echo "${ERROR_FILE}" | sed "s/.err$//g")
		if [ -f "${ORIGINAL_FILE}" ]
		then
			rm ${ERROR_FILE}
		# If the original file does not exist, changes it back to the original name to test it.
		else
			mv ${ERROR_FILE} ${ORIGINAL_FILE}
		fi
	fi

done