#!/bin/sh

# Default script behavior.
set -o errexit
#set -o pipefail

# Default paramterers.
DEBUG=false
DEBUG_OPT=
HAPROXY_PARAMETERS=

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

# Moves front end config to service (persistent) folder.
for CONFIG_FILE in /usr/local/etc/haproxy/10-frontend*
do

	# If the front end config is present in the service folder.
	if [ -f /usr/local/etc/haproxy/service/${CONFIG_FILE} ]
	then
		# Moves the file to the service folder.
		mv /usr/local/etc/haproxy/${CONFIG_FILE} /usr/local/etc/haproxy/service/${CONFIG_FILE}
	
	# If the front end config is present in the service folder.
	else
		rm -f /usr/local/etc/haproxy/${CONFIG_FILE}
		${DEBUG} && echo  "Not moving ${CONFIG_FILE}. File already present."
	fi

done


# Configures intranet ACL to be updated every 10 minutes.
${DEBUG} && echo "Configuring 'haproxy_update_intranet'"


# Starts cron.
env > /etc/docker_env
chmod +x /etc/docker_env
service cron start

# Starts syslog.
readonly RSYSLOG_PID="/var/run/rsyslogd.pid"
rm -f $RSYSLOG_PID
rsyslogd

# Executes the init script.
${DEBUG} && echo "exec /docker-entrypoint.sh haproxy ${HAPROXY_PARAMETERS}"
exec /docker-entrypoint.sh haproxy ${HAPROXY_PARAMETERS}

