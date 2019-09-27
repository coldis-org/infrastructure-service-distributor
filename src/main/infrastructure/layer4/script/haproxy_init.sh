#!/bin/sh

# Default script behavior.
set -o errexit
#set -o pipefail

# Default paramterers.
DEBUG=false
DEBUG_OPT=
HAPROXY_PARAMETERS=
CERT_PATH=/etc/ssl/supersim
CERT_INFO="/C=${CERT_C}/ST=${CERT_ST}/L=${CERT_L}/O=${CERT_O}/OU=${CERT_OU}/CN=${CERT_CN}"

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
			HAPROXY_PARAMETERS="${HAPROXY_PARAMETERS} ${1}"
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
${DEBUG} && echo  "Running 'haproxy_init'"

# Generates certificates.
mkdir -p ${CERT_PATH}
openssl genrsa -out ${CERT_PATH}/supersim-key.pem 2048 
openssl req -new -new -key ${CERT_PATH}/supersim-key.pem -out ${CERT_PATH}/supersim.csr \
	-subj "${CERT_INFO}"
openssl x509 -req -in ${CERT_PATH}/supersim.csr -out ${CERT_PATH}/supersim.crt
cat ${CERT_PATH}/supersim.crt ${CERT_PATH}/supersim.key | \
	tee ${CERT_PATH}/supersim.pem

# Executes the init script.
${DEBUG} && echo "exec /docker-entrypoint.sh haproxy ${HAPROXY_PARAMETERS}"
exec /docker-entrypoint.sh haproxy ${HAPROXY_PARAMETERS}

