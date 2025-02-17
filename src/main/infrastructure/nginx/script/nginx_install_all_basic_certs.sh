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
${DEBUG} && echo "Running 'nginx_install_all_basic_certs'"

# Installs all basic certificates.
nginx_session_ticket --only-if-missing
for CERT_SELF_CN in $(echo ${CERT_SELF_CNS} | sed "s/,/ /g")
do
	nginx_install_cert --self-signed "${CERT_SELF_DOMAIN}/CN=${CERT_SELF_CN}"
done
if [ ! -z "${CERT_SELF_OWN_CN}" ]
then
	nginx_install_cert --self-signed "${CERT_SELF_DOMAIN}/CN=${CERT_SELF_OWN_CN}"
	SELF_DOMAIN="${CERT_SELF_OWN_CN}"
	SELF_DOMAIN_DIR="$(echo "/etc/letsencrypt/selfsigned/${SELF_DOMAIN}" | sed -e "s/\*/_/g")"
	export SELF_DOMAIN SELF_DOMAIN_DIR
fi
