#!/bin/sh

# Pulls the threat blocklist from infrastructure-service-threat-blocklist and
# atomically replaces /etc/nginx/conf.d/include.d/threat-blocklist-ips.conf. Returns 0 when the file
# changed (caller should reload nginx), 1 otherwise — same contract as
# nginx_sync_config so it slots into nginx_update_all_config the same way.
#
# The response is the body of nginx's `geo $threat_blocked` block: one entry
# per line, `<IPv4 or IPv6 address>[/<prefix>] 1;`, plus blank and `#` comment
# lines. Every line is validated before the file is replaced; one bad line
# keeps the previous list. Refused as entries: blanket prefixes (IPv4 shorter
# than /8, IPv6 shorter than /16) and private, loopback, link-local and
# shared ranges, so a bad list cannot block the whole internet or the
# cluster's own networks.
#
# An empty list is written only when it is explicit: a body made of comment
# lines (e.g. `# empty`) clears the blocklist. A zero-byte body is treated as
# a failed pull and keeps the previous list.

# Update environment variables.
ENV_FILE="/local/application.env"
if [ -f "$ENV_FILE" ]; then
  . "$ENV_FILE"
fi

# Default parameters.
DEBUG=${DEBUG:=false}
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

rm -f "${TMP_NEW}"
if [ -n "${THREAT_BLOCKLIST_TOKEN}" ]
then
	wget -q -O "${TMP_NEW}" --timeout="${THREAT_BLOCKLIST_TIMEOUT}" --tries=1 \
		--header="Authorization: Bearer ${THREAT_BLOCKLIST_TOKEN}" \
		"${THREAT_BLOCKLIST_URL}"
else
	wget -q -O "${TMP_NEW}" --timeout="${THREAT_BLOCKLIST_TIMEOUT}" --tries=1 \
		"${THREAT_BLOCKLIST_URL}"
fi
WGET_STATUS=$?
if [ ${WGET_STATUS} -ne 0 ]
then
	# Keep last-good file on transport failure.
	echo "nginx_update_threat_blocklist: pull failed (wget exit ${WGET_STATUS}); keeping previous blocklist."
	rm -f "${TMP_NEW}"
	return 1
fi

if [ ! -s "${TMP_NEW}" ]
then
	echo "nginx_update_threat_blocklist: downloaded file is empty (zero bytes); keeping previous blocklist. An intentional empty list is a body of comment lines."
	rm -f "${TMP_NEW}"
	return 1
fi

# Validates every line; prints the offending ones (with line numbers) and
# exits non-zero on the first file that has any. POSIX awk only (mawk in the
# image): no interval expressions.
INVALID_LINES=$(awk '
	function octet(value) { return value ~ /^[0-9]+$/ && value + 0 <= 255 }
	function bad(reason) { printf "  line %d (%s): %s\n", NR, reason, $0; status = 1 }
	BEGIN { status = 0 }
	{ sub(/\r$/, "") }
	/^[ \t]*$/ || /^[ \t]*#/ { next }
	{
		if ($0 !~ /^[0-9A-Fa-f.:\/]+[ \t]+1;[ \t]*$/) { bad("not \"<address>[/<prefix>] 1;\""); next }
		entry = $1
		prefix = -1
		slash = index(entry, "/")
		if (slash > 0) {
			prefix_text = substr(entry, slash + 1)
			if (prefix_text !~ /^[0-9]+$/) { bad("prefix is not a number"); next }
			prefix = prefix_text + 0
			entry = substr(entry, 1, slash - 1)
		}
		if (entry ~ /:/) {
			if (prefix > 128) { bad("IPv6 prefix above 128"); next }
			if (prefix >= 0 && prefix < 16) { bad("IPv6 prefix shorter than /16"); next }
			lower = tolower(entry)
			if (lower == "::" || lower == "::1" || lower ~ /^f[cd]/ || lower ~ /^fe[89ab]/) { bad("private, loopback or link-local IPv6"); next }
			next
		}
		count = split(entry, octets, ".")
		if (count != 4 || !octet(octets[1]) || !octet(octets[2]) || !octet(octets[3]) || !octet(octets[4])) { bad("not an IPv4 address"); next }
		if (prefix > 32) { bad("IPv4 prefix above 32"); next }
		if (prefix >= 0 && prefix < 8) { bad("IPv4 prefix shorter than /8"); next }
		first = octets[1] + 0; second = octets[2] + 0
		if (first == 0 || first == 10 || first == 127 \
		    || (first == 100 && second >= 64 && second <= 127) \
		    || (first == 169 && second == 254) \
		    || (first == 172 && second >= 16 && second <= 31) \
		    || (first == 192 && second == 168)) { bad("private, loopback, link-local or shared IPv4"); next }
	}
	END { exit status }
' "${TMP_NEW}")
if [ $? -ne 0 ]
then
	echo "nginx_update_threat_blocklist: downloaded list has invalid entries; keeping previous blocklist."
	printf '%s\n' "${INVALID_LINES}" | head -20
	rm -f "${TMP_NEW}"
	return 1
fi

if [ -f "${THREAT_BLOCKLIST_TARGET}" ] && cmp -s "${TMP_NEW}" "${THREAT_BLOCKLIST_TARGET}"
then
	${DEBUG} && echo "Threat blocklist unchanged; not reloading."
	rm -f "${TMP_NEW}"
	return 1
fi

mv "${TMP_NEW}" "${THREAT_BLOCKLIST_TARGET}"
chown nginx:nginx "${THREAT_BLOCKLIST_TARGET}" 2>/dev/null || true
ENTRIES=$(grep -cvE '^[[:space:]]*(#|$)' "${THREAT_BLOCKLIST_TARGET}")
echo "nginx_update_threat_blocklist: blocklist updated (${ENTRIES} entries). Should reload."
return 0
