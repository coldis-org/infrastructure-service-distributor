#!/bin/sh

# Default script behavior.
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
CERT_CLEANUP=${CERT_CLEANUP:=false}

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
${DEBUG} && echo "Running 'nginx_cert_cleanup'"

# Only runs if cleanup is enabled.
if ! ${CERT_CLEANUP}
then
	${DEBUG} && echo "Certificate cleanup is disabled. Set CERT_CLEANUP=true to enable."
	return 0
fi

# Removes duplicate certificate directories ending in -00N (e.g. domain.com-0001).
duplicate_pattern="-[0-9][0-9][0-9][0-9]"
for cert_dir in /etc/letsencrypt/live /etc/letsencrypt/archive /etc/letsencrypt/renewal
do
	if [ -d "${cert_dir}" ]
	then
		for entry in ${cert_dir}/*${duplicate_pattern}*
		do
			if [ -e "${entry}" ]
			then
				echo "nginx_cert_cleanup: Removing duplicate certificate entry ${entry}"
				rm -rf "${entry}"
			fi
		done
	fi
done
