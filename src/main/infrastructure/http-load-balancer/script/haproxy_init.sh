#!/bin/sh

# Default script behavior.
set -o errexit
#set -o pipefail

# Debug is disabled by default.
DEBUG=false
DEBUG_OPT=

# Default paramterers.
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

# Executes the init script.
${DEBUG} && echo "exec /docker-entrypoint.sh haproxy ${HAPROXY_PARAMETERS}"
exec /docker-entrypoint.sh haproxy ${HAPROXY_PARAMETERS}

