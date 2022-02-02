#!/bin/sh

# Default script behavior.
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
ONLY_IF_MISSING=false
TICKER_FOLDER=/etc/letsencrypt/ticket

# For each argument.
while :; do
	case ${1} in
		
		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
			;;
		
		# Only if missing.
		--only-if-missing)
			ONLY_IF_MISSING=true
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
${DEBUG} && echo "Running 'nginx_session_ticket'"

mkdir -p ${TICKER_FOLDER}
if [ "${ONLY_IF_MISSING}" = "false" ] || [ ! -f ${TICKER_FOLDER}/current.key ] || [ ! -f ${TICKER_FOLDER}/previous.key ]
then

	# Moves the current ticket to previous.
	if [ ! -f ${TICKER_FOLDER}/current.key ] || [ ! -f ${TICKER_FOLDER}/previous.key ]
	then
		# Makes sure both tickets exist.
		openssl rand 80 > ${TICKER_FOLDER}/previous.key
		openssl rand 80 > ${TICKER_FOLDER}/current.key
	else
		rm -f ${TICKER_FOLDER}/previous.key
		mv ${TICKER_FOLDER}/current.key ${TICKER_FOLDER}/previous.key
	fi

	# Renew the new cert.
	${NO_CERT_RENEW} || openssl rand 80 > ${TICKER_FOLDER}/current.key

fi




