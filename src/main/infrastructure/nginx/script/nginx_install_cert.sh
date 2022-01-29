#!/bin/sh

# Default script behavior.
set -o errexit
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
DOMAINS=
SELF_SIGNED=false

# For each argument.
while :; do
	case ${1} in
		
		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
			;;
			
		# Self signed.
		--self-signed)
			SELF_SIGNED=true
			;;
			
		# Other option.
		?*)
			DOMAINS="${DOMAINS} -d ${1}"
			;;

		# No more options.
		*)
			break

	esac 
	shift
done

# Unascape variables.
DOMAINS=`eval "echo ${DOMAINS}"`

# Using unavaialble variables should fail the script.
set -o nounset

# Enables interruption signal handling.
trap - INT TERM

# Print arguments if on debug mode.
${DEBUG} && echo "Running 'nginx_add_vhost'"
${DEBUG} && echo "DOMAINS=${DOMAINS}"


# Installs the cert.
if [ "${SELF_SIGNED}" = "true" ]
then
	CERT_FOLDER="/etc/letsecnrypt/selfsigned/$(echo ${DOMAINS} | sed 's/.*CN=//g')"
	openssl req -new -x509 -sha256 -newkey rsa:2048 -nodes -days 365 -keyout ${CERT_FOLDER}/key.pem -out ${CERT_FOLDER}/cert.pem -subj "${DOMAINS}"
else 
	certbot certonly --expand --webroot --http-01-port ${CERTBOT_PORT} -w /usr/share/nginx/html \
		--non-interactive --agree-tos --email technology@${HOST_NAME} ${DOMAINS}
fi