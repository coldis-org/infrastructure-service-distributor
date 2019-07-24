#!/bin/sh

# Default script behavior.
set -o errexit
#set -o pipefail

# Default parameters.
DEBUG=false
DEBUG_OPT=
DOMAINS=

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
${DEBUG} && echo "Running 'apache_add_vhost'"
${DEBUG} && echo "DOMAINS=${DOMAINS}"


# Installs the cert.
certbot certonly --expand --webroot -w /usr/local/apache2/htdocs/ \
	--non-interactive --agree-tos --email technology@${HOST_NAME} ${DOMAINS}

# Reloads the configuration.
/usr/local/apache2/bin/httpd -k graceful
