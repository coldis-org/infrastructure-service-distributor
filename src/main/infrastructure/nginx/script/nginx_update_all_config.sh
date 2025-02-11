#!/bin/sh

# Default script behavior.
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=

# For each argument.
while :; do
	case ${1} in
		
		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
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
${DEBUG} && echo "Running 'nginx_update_all_config'"

# If configuration should be reloaded.
SHOULD_RELOAD=false

# Updates network configuration.
if nginx_update_nets ${DEBUG_OPT}
then
    SHOULD_RELOAD=true
fi

# Syncs configuration files.
if nginx_sync_config ${DEBUG_OPT}
then
    SHOULD_RELOAD=true
fi

# Checks configuration and reloads configuration if needed.
ONLY_IF_ERRORS_CHANGE_OPT="--only-if-errors-change"
if ${SHOULD_RELOAD}
then
    ONLY_IF_ERRORS_CHANGE_OPT=""
fi
nginx_check_config ${DEBUG_OPT} ${ONLY_IF_ERRORS_CHANGE_OPT}


