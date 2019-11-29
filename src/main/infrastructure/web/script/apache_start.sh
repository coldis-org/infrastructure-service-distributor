#!/bin/sh

# Default script behavior.
set -o errexit
#set -o pipefail

# Default parameters.
DEBUG=true
DEBUG_OPT=
CMD=

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
			CMD="${CMD} ${1}"
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

# Starts cron.
env > /etc/docker_env
chmod +x /etc/docker_env
service cron start

# Runs the start command.
${DEBUG} && echo "exec ${CMD}"
exec ${CMD}
