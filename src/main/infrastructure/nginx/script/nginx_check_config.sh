#!/bin/sh

# Default script behavior.
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
SKIP_RELOAD=false
SKIP_RELOAD_PARAM=""
RELOAD_ONLY_IF_ERRORS_CHANGE=false
NO_ERROR_FILES_NAME_PATTERN=/etc/nginx/*/*.conf

# For each argument.
while :; do
	case ${1} in
		
		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
			;;
			
		# If actual reload should be done only if errors change.
		--only-if-errors-change)
			RELOAD_ONLY_IF_ERRORS_CHANGE=true
			;;
			
		# If actual reload should be done.
		--no-reload)
			SKIP_RELOAD=true
			SKIP_RELOAD_PARAM="--no-reload"
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
${DEBUG} && echo "Running 'nginx_check_config'"

# Error files.
INITIAL_NO_ERROR_FILES=$(ls ${NO_ERROR_FILES_NAME_PATTERN} || true)
nginx_revert_config_errors ${DEBUG_OPT}

# Test files with errors.
${DEBUG} && nginx -t || true
NGINX_TEST="$( nginx -t 2>&1 )"
${DEBUG} && echo "NGINX_TEST=${NGINX_TEST}"
NGINX_ERROR="$( echo ${NGINX_TEST} | grep emerg )"
CONFIG_VALID=true
LAST_NGINX_ERROR_FILE=
CERT_ERROR=
while [ ! -z "${NGINX_ERROR}" ]
do
	CONFIG_VALID=false
	echo "NGINX_ERROR=${NGINX_ERROR}"
	# Removes files with errors.
	NGINX_ERROR_FILE=$(echo ${NGINX_ERROR} | sed -e "s/.*\[emerg\]//g" -e "s/[^\/]* \//\//" -e "s/[: ].*//g")
    # Check if is not a certificate error
    if [ -z "${NGINX_ERROR_FILE}" ]
    then
        CERT_ERROR=$(echo ${NGINX_ERROR} | grep "cannot load certificate" | sed -e "s#.*/etc/letsencrypt/live/##g" -e "s#/fullchain.pem.*##g" )
        NGINX_ERROR_FILE=$(grep -m 1 ${CERT_ERROR} /etc/nginx/vhost.d/* | cut -d: -f1 | grep https)
		echo "Certificate $CERT_ERROR not found"
    fi
	# If it is the main file, breaks.
	if [ "${NGINX_ERROR_FILE}" = "/etc/nginx/nginx.conf" ] || [ "${LAST_NGINX_ERROR_FILE}" = "${NGINX_ERROR_FILE}" ]
	then
		echo "Main file with error. Nothing to do."
		break
	fi
	LAST_NGINX_ERROR_FILE=${NGINX_ERROR_FILE}
	echo "Moving file ${NGINX_ERROR_FILE} to ${NGINX_ERROR_FILE}.err"
	rm -f ${NGINX_ERROR_FILE}.err
	mv ${NGINX_ERROR_FILE} ${NGINX_ERROR_FILE}.err
	NGINX_TEST="$( nginx -t 2>&1 | cat )"
	${DEBUG} && echo "${NGINX_TEST}"
	NGINX_ERROR="$( echo ${NGINX_TEST} | grep emerg )"
	${DEBUG} && echo ${NGINX_ERROR}
done
FINAL_NO_ERROR_FILES=$(ls ${NO_ERROR_FILES_NAME_PATTERN} || true)

# Checks if there are new configuration files withou errors.
SHOULD_CONTAIN_LIST=${INITIAL_NO_ERROR_FILES}
TO_BE_CONTAINED_LIST=${FINAL_NO_ERROR_FILES}
NEW_FILES_WITHOUT_ERRORS=false
for TO_BE_CONTAINED_ITEM in ${TO_BE_CONTAINED_LIST}
do
	if ! echo ${SHOULD_CONTAIN_LIST} | grep -q ${TO_BE_CONTAINED_ITEM}
    then
    	echo "New file without errors: ${TO_BE_CONTAINED_ITEM}"
        NEW_FILES_WITHOUT_ERRORS=true
        break
    fi
done
${DEBUG} && echo "NEW_FILES_WITHOUT_ERRORS=${NEW_FILES_WITHOUT_ERRORS}"

# Reloads configuration.
SHOULD_RELOAD=false
if ${SKIP_RELOAD}
then
    echo "No reloading defined."
else
    if ${RELOAD_ONLY_IF_ERRORS_CHANGE}
    then
    	if ${NEW_FILES_WITHOUT_ERRORS}
    	then
    		echo "New configuration files without errors."
    		SHOULD_RELOAD=true
    	else
    	    echo "No new configuration files without errors. Skipping reload."
    		SHOULD_RELOAD=false
    	fi
    else
    	SHOULD_RELOAD=true
    fi
fi
if ${SHOULD_RELOAD}
then
	echo "Reloading configuration."
	${SKIP_RELOAD} || nginx_variables ${SKIP_RELOAD_PARAM}
	${SKIP_RELOAD} || nginx -s reload
fi

# Returns if the configuration is valid.
if ${CONFIG_VALID}
then
	return 0
else 
	return 1
fi