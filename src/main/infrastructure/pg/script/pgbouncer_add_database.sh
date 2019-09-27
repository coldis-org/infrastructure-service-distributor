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
			
		# Database name.
		-d|--database-name)
			DATABASE_NAME=${2}
			shift
			;;
			
		# Database config.
		-c|--database-config)
			DATABASE_CONFIG=${2}
			shift
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
${DEBUG} && echo "Running 'pgboucer_add_database'"
${DEBUG} && echo "DATABASE_NAME=${DATABASE_NAME}"
${DEBUG} && echo "DATABASE_CONFIG=${DATABASE_CONFIG}"
${DEBUG} && echo "DATABASE=${DATABASE}"

# If the database is configured.
if cat ${CONFIG_DIR}/database/database.ini | grep "${DATABASE_NAME} ="
then
	# Adds the new configuration.
	sed -i "s/^${DATABASE_NAME} = [^\\n]*/${DATABASE_NAME} = ${DATABASE_CONFIG}/" ${CONFIG_DIR}/database/database.ini
# If the database is not configured.
else 
	# Adds the new configuration.
	echo "${DATABASE_NAME} = ${DATABASE_CONFIG}/" >> ${CONFIG_DIR}/database/database.ini
fi

# Reloads the configuration.
kill -HUP 1

