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

# Starts the http cache clean job.
${DEBUG} && echo "Running 'apache_check_cache_cleaner'"
apache_start_cache_cleaner ${DEBUG_OPT} &

# Configures intranet ACL to be updated every 10 minutes.
${DEBUG} && echo "Configuring 'apache_update_intranet'"
apache_update_intranet --debug &

# Runs the start command.
${DEBUG} && echo "exec ${CMD}"
exec ${CMD}
