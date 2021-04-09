#!/bin/sh

# Default script behavior.
set -o errexit
#set -o pipefail

# Default paramterers.
DEBUG=${DEBUG:=false}
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

