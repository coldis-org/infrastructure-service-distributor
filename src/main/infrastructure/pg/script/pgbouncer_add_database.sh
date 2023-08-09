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

# Regular expression pattern to match the desired database connection format
PATTERN="^([a-zA-Z0-9_-]+) = host=([a-zA-Z0-9.-]+) port=([0-9]+) dbname=([a-zA-Z0-9_-]+)( user=([a-zA-Z0-9_-]+))?( password=([a-zA-Z0-9_-]+))?$"

# Check database string is valid.
DB_CONNECTION="${DATABASE_NAME} = ${DATABASE_CONFIG}"
if echo "$DB_CONNECTION" | grep -Eq "$PATTERN"; then
	echo "Valid database connection: $DB_CONNECTION"
else
	echo "Invalid database connection: $DB_CONNECTION"
	exit 1   
fi

# If the database is configured.
if cat ${PGBOUNCER_CONFIG}/database/database.ini | grep -w "${DATABASE_NAME} ="
then
	# Adds the new configuration.
	sed -i "s/^${DATABASE_NAME} = [^\\n]*/${DATABASE_NAME} = ${DATABASE_CONFIG}/" ${PGBOUNCER_CONFIG}/database/database.ini
# If the database is not configured.
else 
	# Adds the new configuration.
	echo "${DATABASE_NAME} = ${DATABASE_CONFIG}" >> ${PGBOUNCER_CONFIG}/database/database.ini
fi

# Reloads the configuration.
kill -HUP 1

