#!/bin/sh

# Default script behavior.
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
CERT_CLEANUP=${CERT_CLEANUP:=false}
CERT_CLEANUP_TEMP_MAX_DAYS=${CERT_CLEANUP_TEMP_MAX_DAYS:=7}

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
for cert_dir in /etc/letsencrypt/live /etc/letsencrypt/archive
do
	if [ -d "${cert_dir}" ]
	then
		for entry in ${cert_dir}/*${duplicate_pattern}
		do
			if [ -e "${entry}" ]
			then
				echo "nginx_cert_cleanup: Removing duplicate certificate entry ${entry}"
				rm -rf "${entry}"
			fi
		done
	fi
done
# Renewal uses .conf files, so the pattern ends with -00N.conf.
if [ -d "/etc/letsencrypt/renewal" ]
then
	for entry in /etc/letsencrypt/renewal/*${duplicate_pattern}.conf
	do
		if [ -e "${entry}" ]
		then
			echo "nginx_cert_cleanup: Removing duplicate certificate entry ${entry}"
			rm -f "${entry}"
		fi
	done
fi

# Removes temporary certificate directories (tmp-*, www-tmp*, www.tmp*) older than configured days.
${DEBUG} && echo "Checking for temporary certificates older than ${CERT_CLEANUP_TEMP_MAX_DAYS} days"
live_dir=/etc/letsencrypt/live
if [ -d "${live_dir}" ]
then
	for entry in ${live_dir}/tmp-* ${live_dir}/www-tmp* ${live_dir}/www.tmp*
	do
		if [ -d "${entry}" ]
		then
			# Checks if directory is older than max days.
			entry_age_days=$(( ( $(date +%s) - $(stat --format '%W' "${entry}") ) / 86400 ))
			if [ ${entry_age_days} -ge ${CERT_CLEANUP_TEMP_MAX_DAYS} ]
			then
				cert_name=$(basename "${entry}")
				echo "nginx_cert_cleanup: Removing temporary certificate '${cert_name}' (${entry_age_days} days old)"
				rm -rf "/etc/letsencrypt/live/${cert_name}"
				rm -rf "/etc/letsencrypt/archive/${cert_name}"
				rm -f "/etc/letsencrypt/renewal/${cert_name}.conf"
			fi
		fi
	done
fi
