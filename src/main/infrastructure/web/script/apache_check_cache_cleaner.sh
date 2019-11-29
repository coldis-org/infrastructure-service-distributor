#!/bin/sh

# Default script behavior.
set -o errexit
#set -o pipefail

# Default parameters.
DEBUG=false
DEBUG_OPT=

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

# Print arguments if on debug mode.
${DEBUG} && echo "Running 'apache_check_cache_cleaner'"

# If the cache cleaner is not running.
if pgrep -fl htcacheclean
then 
	${DEBUG} && echo "Cache cleaner running."
else
	${DEBUG} && echo "Cache cleaner not running. Restarting..."
	apache_start_cache_cleaner &
	${DEBUG} && echo "Cache cleaner restarted..."
	exit 1
fi