#!/bin/sh

# Default script behavior.
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
			printf 'nginx_update_security_rules: [WARN] Unknown option (ignored): %s\n' "$1" >&2
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
${DEBUG} && echo "nginx_update_security_rules: [DEBUG] Running"

# Diff output (full file contents) is only useful for debugging; hide it otherwise.
DIFF_OUT=/dev/null
${DEBUG} && DIFF_OUT=/dev/stdout

# Default parameters.
CONFIG_UPDATED=false

# Removes temporary files.
rm -f ${OLD_REQUEST_EXCLUSIONS_FILE} ${NEW_REQUEST_EXCLUSIONS_FILE} 

# Prepares network config.
REQUEST_EXCLUSIONS_FILE=/etc/modsecurity/crs/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
if [ ! -f ${REQUEST_EXCLUSIONS_FILE} ]
then
    touch ${REQUEST_EXCLUSIONS_FILE}
fi
OLD_REQUEST_EXCLUSIONS_FILE=/tmp/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.old
NEW_REQUEST_EXCLUSIONS_FILE=/tmp/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.new
cp -f ${REQUEST_EXCLUSIONS_FILE} ${OLD_REQUEST_EXCLUSIONS_FILE}
cp -f ${REQUEST_EXCLUSIONS_FILE}.default ${NEW_REQUEST_EXCLUSIONS_FILE}

# Removes anything after generated content comment.
sed '/# Automated exclusions\. Any rules after this line will be replaced\./,$d' ${NEW_REQUEST_EXCLUSIONS_FILE} > ${NEW_REQUEST_EXCLUSIONS_FILE}

# Reloads the configuration if the file has been updated.
if  ( ! diff "${OLD_REQUEST_EXCLUSIONS_FILE}" "${NEW_REQUEST_EXCLUSIONS_FILE}" >${DIFF_OUT} 2>&1 )
then
    CONFIG_UPDATED=true
fi
${DEBUG} && echo "nginx_update_security_rules: [DEBUG] CONFIG_UPDATED=${CONFIG_UPDATED}"
if ${CONFIG_UPDATED}
then
	cp -f ${NEW_REQUEST_EXCLUSIONS_FILE} ${REQUEST_EXCLUSIONS_FILE}
fi

# Removes temporary files.
rm -f ${OLD_REQUEST_EXCLUSIONS_FILE} ${NEW_REQUEST_EXCLUSIONS_FILE} 

# Returns if the configuration was updated.
if ${CONFIG_UPDATED}
then
	echo "nginx_update_security_rules: [INFO] Changes detected in exclusion files. Should reload configuration."
	return 0
else 
	echo "nginx_update_security_rules: [INFO] No changes detected in exclusion files. Should not reload configuration."
	return 1
fi

