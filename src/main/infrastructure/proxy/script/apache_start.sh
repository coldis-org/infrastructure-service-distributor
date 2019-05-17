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

# Print arguments if on debug mode.
${DEBUG} && echo "Running 'apache_check_cache_cleaner'"

# Starts the http cache clean job.
apache_start_cache_cleaner ${DEBUG_OPT} &

# Runs the start command.
${DEBUG} && echo "exec ${CMD}"
exec ${CMD}
