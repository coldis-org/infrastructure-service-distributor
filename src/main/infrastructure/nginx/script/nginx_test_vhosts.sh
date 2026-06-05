#!/bin/sh

# Default script behavior.
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
conf_folder=/etc/nginx/
vhosts_folder=/etc/nginx/vhost.d
error_counts_file=/etc/nginx/.config_error_counts
error_pattern="\[emerg\]"
fragment=
report_only=false

# For each argument.
while :; do
	case ${1} in

		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
			;;

		# Only test files that include this fragment (an include.d/*.conf path).
		--fragment)
			fragment=${2}
			shift
			;;

		# Report broken files without quarantining them (leaves config untouched).
		--report-only)
			report_only=true
			;;

		# Other option.
		?*)
			printf 'nginx_test_vhosts: [WARN] Unknown option (ignored): %s\n' "$1" >&2
			;;

		# No more options.
		*)
			break

	esac
	shift
done

# Enables interruption signal handling.
trap - INT TERM

${DEBUG} && echo "nginx_test_vhosts: [DEBUG] Running"

# Builds the candidate list.
if [ -n "${fragment}" ]
then
	# Files that include the given fragment (matched by basename), excluding the
	# fragments themselves and any already-quarantined .err files.
	fragment_base=$( basename "${fragment}" )
	${DEBUG} && echo "nginx_test_vhosts: [DEBUG] Looking for files that include ${fragment_base}"
	candidates=$( grep -rlEI "include[[:space:]]+[^;]*${fragment_base}" \
			"${conf_folder}conf.d" "${conf_folder}vhost.d" 2>/dev/null \
		| grep -E '\.conf$' \
		| grep -v '/include.d/' )
else
	# All active vhosts.
	candidates=$( find "${vhosts_folder}" -type f -name '*.conf' 2>/dev/null )
fi

# Nothing to test.
if [ -z "${candidates}" ]
then
	echo "nginx_test_vhosts: [WARN] No candidate files to test${fragment:+ for fragment ${fragment}}."
	return 0
fi

# Removes all candidates so they can be added back one at a time and tested in isolation
# while keeping the full shared context (maps, upstreams, zones) in place.
${DEBUG} && echo "nginx_test_vhosts: [DEBUG] Removing $( echo "${candidates}" | wc -w | tr -d ' ' ) candidate(s) before re-testing one by one"
for candidate in ${candidates}
do
	mv -f "${candidate}" "${candidate}.err"
done

# In audit mode (no fragment) the baseline with all candidates removed must be valid,
# otherwise an unrelated error would make every add-back look broken. In fragment mode
# this is not needed: a file is only flagged if it re-introduces the fragment error.
if [ -z "${fragment}" ]
then
	baseline=$( nginx -t 2>&1 1>/dev/null | grep "${error_pattern}" )
	if [ -n "${baseline}" ]
	then
		echo "nginx_test_vhosts: [ERROR] Configuration is invalid even with all vhosts removed; the error is not in the vhosts. Restoring and aborting."
		${DEBUG} && echo "nginx_test_vhosts: [DEBUG] ${baseline}"
		for candidate in ${candidates}
		do
			mv -f "${candidate}.err" "${candidate}"
		done
		return 1
	fi
fi

# Adds the candidates back one by one, keeping the valid ones and quarantining the broken ones.
broken_count=0
for candidate in ${candidates}
do
	mv -f "${candidate}.err" "${candidate}"
	test_output=$( nginx -t 2>&1 1>/dev/null )

	# Determines whether this candidate is broken.
	is_broken=false
	if [ -n "${fragment}" ]
	then
		# Fragment mode: broken only if adding it back re-introduces the fragment error.
		if echo "${test_output}" | grep -q -F "${fragment}"
		then
			is_broken=true
		fi
	else
		# Audit mode: broken if adding it back makes the configuration invalid.
		if echo "${test_output}" | grep -q "${error_pattern}"
		then
			is_broken=true
		fi
	fi

	if ${is_broken}
	then
		broken_count=$(( broken_count + 1 ))
		reason=$( echo "${test_output}" | sed "s/.*${error_pattern}//" | sed 's/ nginx: configuration file .* test failed//' )
		echo "nginx_test_vhosts: [WARN] Broken file ${candidate}:${reason}"

		if ${report_only}
		then
			# Pure report: leave the file active so the config is unchanged.
			:
		else
			# Quarantines the broken file.
			mv -f "${candidate}" "${candidate}.err"

			# Increments the error count for the file (only if MAX_CONFIG_ERROR_COUNT is set).
			if [ ! -z "${MAX_CONFIG_ERROR_COUNT}" ]
			then
				touch ${error_counts_file}
				current_count=$( grep "^${candidate} " ${error_counts_file} 2>/dev/null | awk '{print $NF}' | tr -dc '0-9' )
				current_count=${current_count:-0}
				new_count=$((current_count + 1))
				sed -i "\#^${candidate} #d" ${error_counts_file}
				echo "${candidate} ${new_count}" >> ${error_counts_file}
				${DEBUG} && echo "nginx_test_vhosts: [DEBUG] Error count for ${candidate}: ${new_count}"
			fi
		fi
	else
		${DEBUG} && echo "nginx_test_vhosts: [DEBUG] OK ${candidate}"
	fi
done

echo "nginx_test_vhosts: [INFO] Tested $( echo "${candidates}" | wc -w | tr -d ' ' ) file(s); ${broken_count} broken."
return 0
