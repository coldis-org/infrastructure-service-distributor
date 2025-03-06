#!/bin/sh

# Default script behavior.
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
DOMAINS=
SELF_SIGNED=false
EXPORT_SELF_DOMAIN=false
ONLY_IF_MISSING=false
FORCE_RENEW_ARG=

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

		# Only if missing.
		--only-if-missing)
            ONLY_IF_MISSING=true
            ;;
		
		# Force renew
		--force-renew)
			FORCE_RENEW_ARG="--force-renew"
			;;
			
		# Other option.
		?*)
			if [ "${SELF_SIGNED}" = "true" ]
			then
				DOMAINS="${DOMAINS} ${1}"
			else 
				DOMAINS="${DOMAINS} -d ${1}"
			fi
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

	# Generates self signed cert.
	DOMAIN="$(echo ${DOMAINS} | sed 's/.*CN=//g')"
	CERT_FOLDER=$(echo "/etc/letsencrypt/selfsigned/${DOMAIN}" | sed -e "s/\*/_/g")
	mkdir -p ${CERT_FOLDER}
	if ( ! ${ONLY_IF_MISSING} ) || ( [ ! -f ${CERT_FOLDER}/key.pem ] || [ ! -f ${CERT_FOLDER}/cert.pem ] )
	then
		TEMP_CERT_CONF_FILE=$(echo "/tmp/${DOMAIN}-cert.conf" | sed -e "s/\*/_/g")
		cat /etc/ssl/openssl.cnf > ${TEMP_CERT_CONF_FILE}
		echo "[SAN]\nsubjectAltName=DNS:${DOMAIN}" >> ${TEMP_CERT_CONF_FILE}
		openssl req -newkey rsa:4096 -new -x509 -sha256 -reqexts SAN -extensions SAN -nodes -days 365 -keyout ${CERT_FOLDER}/key.pem -out ${CERT_FOLDER}/cert.pem -subj "${DOMAINS}" -config ${TEMP_CERT_CONF_FILE}
		rm ${TEMP_CERT_CONF_FILE}
	fi
	
# Otherwise, use certbot.
else 
	certbot certonly --expand --webroot --http-01-port ${CERTBOT_PORT} -w /usr/share/nginx/html \
		--non-interactive --agree-tos --email technology@${HOST_NAME} ${FORCE_RENEW_ARG} ${DOMAINS}
fi
