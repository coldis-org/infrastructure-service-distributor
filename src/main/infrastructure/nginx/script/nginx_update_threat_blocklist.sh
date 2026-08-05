#!/bin/sh

# Pulls the threat blocklist from infrastructure-service-threat-blocklist and
# atomically replaces /etc/nginx/conf.d/include.d/threat-blocklist-ips.conf. Returns 0 when the file
# changed (caller should reload nginx), 1 otherwise — same contract as
# nginx_sync_config so it slots into nginx_update_all_config the same way.

# Default script behavior.
#set -o pipefail

# Update environment variables.
ENV_FILE="/local/application.env"
if [ -f "$ENV_FILE" ]; then
  . "$ENV_FILE"
fi

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
THREAT_BLOCKLIST_URL=${THREAT_BLOCKLIST_URL:=}
THREAT_BLOCKLIST_TOKEN=${THREAT_BLOCKLIST_TOKEN:=}
THREAT_BLOCKLIST_TARGET=${THREAT_BLOCKLIST_TARGET:=/etc/nginx/conf.d/include.d/threat-blocklist-ips.conf}
THREAT_BLOCKLIST_TIMEOUT=${THREAT_BLOCKLIST_TIMEOUT:=10}
TMP_NEW=/tmp/threat-blocklist-ips.conf.new

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

# Using unavailable variables should fail the script.
set -o nounset

# Enables interruption signal handling.
trap - INT TERM

# Print arguments if on debug mode.
${DEBUG} && echo "Running 'nginx_update_threat_blocklist'"
${DEBUG} && echo "THREAT_BLOCKLIST_URL=${THREAT_BLOCKLIST_URL}"
${DEBUG} && echo "THREAT_BLOCKLIST_TARGET=${THREAT_BLOCKLIST_TARGET}"

# Skip when not configured (typical for local/dev).
if [ -z "${THREAT_BLOCKLIST_URL}" ]
then
	${DEBUG} && echo "THREAT_BLOCKLIST_URL not set; skipping pull."
	return 1
fi

# Append /blocklist if missing — templates typically provide just host:port.
THREAT_BLOCKLIST_URL="${THREAT_BLOCKLIST_URL%/}"
case "${THREAT_BLOCKLIST_URL}" in
	*/blocklist) ;;
	*) THREAT_BLOCKLIST_URL="${THREAT_BLOCKLIST_URL}/blocklist" ;;
esac

if [ -n "${THREAT_BLOCKLIST_TOKEN}" ]
then
	wget -q -O ${TMP_NEW} --timeout=${THREAT_BLOCKLIST_TIMEOUT} --tries=1 \
		--header="Authorization: Bearer ${THREAT_BLOCKLIST_TOKEN}" \
		"${THREAT_BLOCKLIST_URL}"
else
	wget -q -O ${TMP_NEW} --timeout=${THREAT_BLOCKLIST_TIMEOUT} --tries=1 \
		"${THREAT_BLOCKLIST_URL}"
fi
WGET_STATUS=$?
if [ ${WGET_STATUS} -ne 0 ]
then
	# Keep last-good file on transport failure.
	echo "nginx_update_threat_blocklist: pull failed (wget exit ${WGET_STATUS}); keeping previous blocklist."
	rm -f ${TMP_NEW}
	return 1
fi

if [ ! -s ${TMP_NEW} ]
then
	echo "nginx_update_threat_blocklist: downloaded file is empty; keeping previous blocklist."
	rm -f ${TMP_NEW}
	return 1
fi

if [ -f ${THREAT_BLOCKLIST_TARGET} ] && cmp -s ${TMP_NEW} ${THREAT_BLOCKLIST_TARGET}
then
	${DEBUG} && echo "Threat blocklist unchanged; not reloading."
	rm -f ${TMP_NEW}
	return 1
fi

mv ${TMP_NEW} ${THREAT_BLOCKLIST_TARGET}
chown nginx:nginx ${THREAT_BLOCKLIST_TARGET} 2>/dev/null || true
echo "nginx_update_threat_blocklist: blocklist updated ($(wc -l < ${THREAT_BLOCKLIST_TARGET}) lines). Should reload."
return 0
