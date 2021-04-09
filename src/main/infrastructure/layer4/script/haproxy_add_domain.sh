#!/bin/sh

# Default script behavior.
set -o errexit
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
TEMP=/tmp
CONFIG_DIR=/usr/local/etc/haproxy/service
FRONT_END_FILE=10-frontend
PROTOCOL_TYPE=tcp

# For each argument.
while :; do
	case ${1} in
		
		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
			;;
			
		# Config dir.
		-c|--config-dir)
			CONFIG_DIR=${2}
			shift
			;;

		# Protocol type.
		-t|--protocol-type)
			PROTOCOL_TYPE=${2}
			shift
			;;

		# Protocol name.
		-p|--protocol)
			PROTOCOL=${2}
			FRONT_END_CONFIG="front_end_${2}"
			shift
			;;

		# Domain name.
		-d|--domain)
			DOMAIN=${2}
			shift
			;;

		# Backend name.
		-b|--backend)
			BACKEND_CONFIG=${2}
			shift
			;;

		# Other option.
		?*)
			printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
			;;

		# No more options.
		*)
			break

	esac 
	shift
done

# Domain config.
DOMAIN_CONFIG=$(echo ${DOMAIN}_${PROTOCOL} | sed "s/\./_/g")

# Using unavaialble variables should fail the script.
set -o nounset

# Enables interruption signal handling.
trap - INT TERM

# Backups the front end configuration.
mkdir -p ${TEMP}
rm -f ${TEMP}/${FRONT_END_FILE}-${PROTOCOL}.cfg
cp ${CONFIG_DIR}/${FRONT_END_FILE}-${PROTOCOL}.cfg ${TEMP}/${FRONT_END_FILE}-${PROTOCOL}.cfg

# Print arguments if on debug mode.
${DEBUG} && echo "Running 'haproxy_add_domain'"
${DEBUG} && echo "CONFIG_DIR=${CONFIG_DIR}"
${DEBUG} && echo "PROTOCOL=${PROTOCOL}"
${DEBUG} && echo "DOMAIN=${DOMAIN}"
${DEBUG} && echo "DOMAIN=${DOMAIN}"
${DEBUG} && echo "DOMAIN_CONFIG=${DOMAIN_CONFIG}"
${DEBUG} && echo "BACKEND_CONFIG=${BACKEND_CONFIG}"

# Removes old domain config.
sed -i "s/.*${DOMAIN_CONFIG}.*//g" ${CONFIG_DIR}/${FRONT_END_FILE}-${PROTOCOL}.cfg
sed -i "s/.*${BACKEND_CONFIG}.*//g" ${CONFIG_DIR}/${FRONT_END_FILE}-${PROTOCOL}.cfg

# Adds the domain config.
if [ "PROTOCOL_TYPE" = "http" ]
then
	sed -i "s/\(Subdomains ${FRONT_END_CONFIG}.*\)/\1\n\tacl ${DOMAIN_CONFIG} hdr\(host\) -i ${DOMAIN}/" ${CONFIG_DIR}/${FRONT_END_FILE}-${PROTOCOL}.cfg
else 
	sed -i "s/\(Subdomains ${FRONT_END_CONFIG}.*\)/\1\n\tacl ${DOMAIN_CONFIG} req.payload(5,${#DOMAIN}) -m ${DOMAIN}/" ${CONFIG_DIR}/${FRONT_END_FILE}-${PROTOCOL}.cfg
fi
sed -i "s/\(Backends ${FRONT_END_CONFIG}.*\)/\1\n\tuse_backend ${BACKEND_CONFIG} if ${DOMAIN_CONFIG}/" ${CONFIG_DIR}/${FRONT_END_FILE}-${PROTOCOL}.cfg

# If the config is not valid.
${DEBUG} && echo "Testing config"
if ! /usr/local/sbin/haproxy -c -f /usr/local/etc/haproxy -f /usr/local/etc/haproxy/service
then
	# Reverts the backup config.
	${DEBUG} && echo "Reverting backup"
	rm -f ${CONFIG_DIR}/${FRONT_END_FILE}-${PROTOCOL}.cfg
	cp ${TEMP}/${FRONT_END_FILE}-${PROTOCOL}.cfg ${CONFIG_DIR}/${FRONT_END_FILE}-${PROTOCOL}.cfg
	exit "Invalid front end config"
else 
	# Reloads the configuration.
	kill -HUP 1
fi
