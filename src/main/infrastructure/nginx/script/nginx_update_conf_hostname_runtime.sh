#! /bin/sh

DEBUG=false
ENV_FILE="/local/application.env"
CERTBOT_FILE="/etc/nginx/conf.d/include.d/certbot.conf"

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
			printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
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

# Update environment variables
if [ -f "$ENV_FILE" ]; then
  . "$ENV_FILE"
fi

# Update web-config address on runtime
${DEBUG} && echo "Running sed -i \"s|http://.*|http://${CONF_HOST_NAME};|\" $CERTBOT_FILE"
sed -i "s|http://.*|http://${CONF_HOST_NAME};|" $CERTBOT_FILE

${DEBUG} && echo "Running nginx_check_config"
nginx_check_config