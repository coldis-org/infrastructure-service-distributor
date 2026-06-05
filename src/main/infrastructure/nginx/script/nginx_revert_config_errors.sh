#!/bin/sh

# Default script behavior.
#set -o pipefail

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
conf_folder=/etc/nginx/
error_files_name_pattern=
custom_pattern=false
state_file=/etc/nginx/.config_retest_state

# Retest backoff schedule (seconds); all tunable via environment.
# A broken file is retested every run during the grace window, then with an
# interval that doubles each day, and is finally given up on (marked .dead).
GRACE=${CONFIG_RETEST_GRACE:=172800}            # 2 days: retest every run
BACKOFF_MIN=${CONFIG_RETEST_BACKOFF_MIN:=3600}  # first interval after grace: 1 hour
BACKOFF_MAX=${CONFIG_RETEST_BACKOFF_MAX:=86400} # cap interval at 24 hours
FORGET=${CONFIG_RETEST_FORGET:=604800}          # 7 days failing: give up (.dead)
DEAD_MAX=${CONFIG_RETEST_DEAD_MAX:=2592000}     # delete .dead after 30 days (0 = keep forever)

# For each argument.
while :; do
	case ${1} in
		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
			;;
		# Error files pattern (explicit pattern disables backoff: simple restore/drop).
		--pattern)
			error_files_name_pattern=${2}
			custom_pattern=true
			shift
			;;
		# No more options.
		*)
			break

	esac
	shift
done

# Enables interruption signal handling.
trap - INT TERM

# Print arguments if on debug mode.
${DEBUG} && echo "nginx_revert_config_errors: [DEBUG] Running"

# Explicit pattern (e.g. synced temp config): simple restore/drop, no backoff/state.
if ${custom_pattern}
then
	for ERROR_FILE in $( find ${conf_folder} -type f -name "${error_files_name_pattern}" )
	do
		[ -f "${ERROR_FILE}" ] || continue
		ORIGINAL_FILE=$( echo "${ERROR_FILE}" | sed 's/\.err$//' )
		if [ -f "${ORIGINAL_FILE}" ]
		then
			rm -f "${ERROR_FILE}"
		else
			mv "${ERROR_FILE}" "${ORIGINAL_FILE}" 2>/dev/null
		fi
	done
	return 0
fi

# Current time (epoch seconds).
now=$( date +%s )
touch "${state_file}" 2>/dev/null

# Prunes state rows whose marker is gone (file recovered or was forgotten). This is
# essential: a stale row would carry an old first-failure time and make the file look
# ancient (and instantly dead) the next time it breaks.
{
	while read -r sf_file sf_first sf_next
	do
		[ -z "${sf_file}" ] && continue
		[ -f "${sf_file}.err" ] && echo "${sf_file} ${sf_first} ${sf_next}"
	done < "${state_file}"
} > "${state_file}.tmp" 2>/dev/null
mv -f "${state_file}.tmp" "${state_file}" 2>/dev/null

# Processes quarantined markers (<file>.conf.err).
for ERROR_FILE in $( find ${conf_folder} -type f -name '*.conf.err' )
do
	[ -f "${ERROR_FILE}" ] || continue
	ORIGINAL_FILE=$( echo "${ERROR_FILE}" | sed 's/\.err$//' )

	# If the active file exists again (recovered or re-synced), the marker is stale.
	if [ -f "${ORIGINAL_FILE}" ]
	then
		rm -f "${ERROR_FILE}"
		sed -i "\#^${ORIGINAL_FILE} #d" "${state_file}" 2>/dev/null
		continue
	fi

	# Looks up the retest state. first_failure is set once and never changes, so
	# age grows monotonically and the file is guaranteed to reach FORGET (no loop).
	entry=$( grep "^${ORIGINAL_FILE} " "${state_file}" 2>/dev/null | head -1 )
	if [ -z "${entry}" ]
	then
		first=${now}
		next=${now}
	else
		first=$( echo "${entry}" | awk '{print $2}' )
		next=$( echo "${entry}" | awk '{print $3}' )
	fi
	age=$(( now - first ))

	# Give up after FORGET: mark .dead (kept for inspection), never retested again.
	if [ "${age}" -ge "${FORGET}" ]
	then
		echo "nginx_revert_config_errors: [INFO] Giving up on ${ORIGINAL_FILE} after $(( age / 86400 )) day(s) failing; marking dead."
		mv -f "${ERROR_FILE}" "${ORIGINAL_FILE}.dead" 2>/dev/null
		touch "${ORIGINAL_FILE}.dead" 2>/dev/null
		sed -i "\#^${ORIGINAL_FILE} #d" "${state_file}" 2>/dev/null
		continue
	fi

	# Not yet due for a retest: keep waiting (back off).
	if [ "${now}" -lt "${next}" ]
	then
		continue
	fi

	# Backoff interval for the current age: every run during grace, then doubling daily.
	if [ "${age}" -lt "${GRACE}" ]
	then
		interval=0
	else
		days_past=$(( (age - GRACE) / 86400 ))
		interval=${BACKOFF_MIN}
		i=0
		while [ "${i}" -lt "${days_past}" ] && [ "${interval}" -lt "${BACKOFF_MAX}" ]
		do
			interval=$(( interval * 2 ))
			i=$(( i + 1 ))
		done
		[ "${interval}" -gt "${BACKOFF_MAX}" ] && interval=${BACKOFF_MAX}
	fi

	# Schedules the next retest and restores the file so this run can test it.
	sed -i "\#^${ORIGINAL_FILE} #d" "${state_file}" 2>/dev/null
	echo "${ORIGINAL_FILE} ${first} $(( now + interval ))" >> "${state_file}"
	${DEBUG} && echo "nginx_revert_config_errors: [DEBUG] Retesting ${ORIGINAL_FILE} (age $(( age / 3600 ))h, next retest in $(( interval / 3600 ))h)"
	mv -f "${ERROR_FILE}" "${ORIGINAL_FILE}" 2>/dev/null
done

# Sweeps .dead files older than DEAD_MAX (0 keeps them forever).
if [ "${DEAD_MAX}" -gt 0 ]
then
	for DEAD_FILE in $( find ${conf_folder} -type f -name '*.conf.dead' )
	do
		[ -f "${DEAD_FILE}" ] || continue
		dead_age=$(( now - $( stat -c %Y "${DEAD_FILE}" ) ))
		if [ "${dead_age}" -ge "${DEAD_MAX}" ]
		then
			${DEBUG} && echo "nginx_revert_config_errors: [DEBUG] Sweeping ${DEAD_FILE} (dead ${dead_age}s)"
			rm -f "${DEAD_FILE}"
		fi
	done
fi
return 0
