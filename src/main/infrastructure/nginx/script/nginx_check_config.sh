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
ERROR_FILES=/etc/nginx/*/*.conf.err
for ERROR_FILE in ${ERROR_FILES}
do
	
	if [ -f "${ERROR_FILE}" ]
	then
		# If the original file exists.
		ORIGINAL_FILE=$(echo "${ERROR_FILE}" | sed "s/.err$//")
		if [ -f "${ORIGINAL_FILE}" ]
		then
			# Removes the error file.
			rm ${ERROR_FILE}
		# If the original file does not exist.
		else
			# Moves the error file back to its original name.
			mv ${ERROR_FILE} ${ORIGINAL_FILE}
		fi
	fi

done

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

# Reloads config.
${SKIP_RELOAD} || nginx_variables ${SKIP_RELOAD_PARAM}
${SKIP_RELOAD} || nginx -s reload

if ${CONFIG_VALID}
then
	return 0
else 
	return 1
fi