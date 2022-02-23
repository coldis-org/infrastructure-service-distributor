#!/bin/sh

# Default script behavior.
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
SKIP_RELOAD=false
VHOST_DIR="/etc/nginx/vhost.d/"

# For each argument.
while :; do
	case ${1} in
		
		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
			;;
			
		# If actual reload should be noed.
		--no-reload)
			SKIP_RELOAD=true
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

# Test if exist any http2 listening to port 80
${DEBUG} && echo "Checking http2 on vhost files"

for file in $(grep -Ro "80[[:blank:]]\+http2" $VHOST_DIR | cut -d ":" -f1); do
   echo "Moving file $file to ERR due invalid http2 directive"
   mv $file $file.err
done

# Test files with errors.
${DEBUG} && nginx -t || true
NGINX_TEST="$( nginx -t 2>&1 )"
${DEBUG} && echo "NGINX_TEST=${NGINX_TEST}"
NGINX_ERROR="$( echo ${NGINX_TEST} | grep emerg )"
CONFIG_VALID=true
LAST_NGINX_ERROR_FILE=
while [ ! -z "${NGINX_ERROR}" ]
do
	CONFIG_VALID=false
	echo "NGINX_ERROR=${NGINX_ERROR}"
	# Removes files with errors.
	NGINX_ERROR_FILE=$(echo ${NGINX_ERROR} | sed -e "s/.*\[emerg\]//g" -e "s/[^\/]* \//\//" -e "s/[: ].*//g")
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
${SKIP_RELOAD} || nginx_variables
${SKIP_RELOAD} || nginx -s reload

if ${CONFIG_VALID}
then
	return 0
else 
	return 1
fi
