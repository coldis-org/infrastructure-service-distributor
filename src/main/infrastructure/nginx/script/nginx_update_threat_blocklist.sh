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
TMP_NEW="${THREAT_BLOCKLIST_TARGET}.new"   # beside the target, so the rename is atomic

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
# The token goes through a wgetrc readable only by this process's user, not
# argv, where any local user could read it in the process list. The URL is
# the service's address inside the cluster network (host:port from the
# deployment), which is why the scheme is not forced to https.
WGET_CONFIG=$(mktemp)
chmod 600 "${WGET_CONFIG}"
if [ -n "${THREAT_BLOCKLIST_TOKEN}" ]
then
	printf 'header = Authorization: Bearer %s\n' "${THREAT_BLOCKLIST_TOKEN}" > "${WGET_CONFIG}"
fi
WGETRC="${WGET_CONFIG}" wget -q -O "${TMP_NEW}" --timeout="${THREAT_BLOCKLIST_TIMEOUT}" --tries=1 \
	"${THREAT_BLOCKLIST_URL}"
WGET_STATUS=$?
rm -f "${WGET_CONFIG}"
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
	# Structure, not only characters: hex groups of 1 to 4 digits, at most
	# one "::", 8 groups without it and fewer with it. No embedded IPv4 (a dot).
	function ipv6(value,    rest, doubles, count, parts, i, empty) {
		if (value ~ /[^0-9a-f:]/) return 0
		rest = value; doubles = gsub(/::/, "::", rest)
		if (doubles > 1 || value ~ /:::/) return 0
		if (doubles == 0 && (value ~ /^:/ || value ~ /:$/)) return 0
		count = split(value, parts, ":")
		empty = 0
		for (i = 1; i <= count; i++) {
			if (parts[i] == "") { empty++; continue }
			if (length(parts[i]) > 4) return 0
		}
		if (doubles == 0) return count == 8 && empty == 0
		return count - empty <= 7
	}
	function bad(reason) { printf "  line %d (%s): %s\n", NR, reason, $0; status = 1 }
	function protect(name, a, b, c, d, bits) {
		protected_count++
		protected_name[protected_count] = name
		protected_start[protected_count] = ((a * 256 + b) * 256 + c) * 256 + d
		protected_end[protected_count] = protected_start[protected_count] + 2 ^ (32 - bits) - 1
	}
	BEGIN {
		status = 0
		protect("0.0.0.0/8", 0, 0, 0, 0, 8); protect("10.0.0.0/8", 10, 0, 0, 0, 8)
		protect("100.64.0.0/10", 100, 64, 0, 0, 10); protect("127.0.0.0/8", 127, 0, 0, 0, 8)
		protect("169.254.0.0/16", 169, 254, 0, 0, 16); protect("172.16.0.0/12", 172, 16, 0, 0, 12)
		protect("192.168.0.0/16", 192, 168, 0, 0, 16)
	}
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
			if (!ipv6(lower)) { bad("not an IPv6 address"); next }
			# ::/8 holds the unspecified, loopback and IPv4-mapped/compatible
			# space, so an entry starting with 0 or :: is refused outright.
			if (lower ~ /^0/ || lower ~ /^::/ || lower ~ /^f[cd]/ || lower ~ /^fe[89ab]/) { bad("private, loopback, link-local or IPv4-mapped IPv6"); next }
			next
		}
		count = split(entry, octets, ".")
		if (count != 4 || !octet(octets[1]) || !octet(octets[2]) || !octet(octets[3]) || !octet(octets[4])) { bad("not an IPv4 address"); next }
		if (prefix > 32) { bad("IPv4 prefix above 32"); next }
		if (prefix >= 0 && prefix < 8) { bad("IPv4 prefix shorter than /8"); next }
		# The whole range of the entry, not only its first address, must stay clear
		# of the protected ranges: 172.0.0.0/8 starts outside 172.16/12 but
		# covers it.
		if (prefix < 0) prefix = 32
		size = 2 ^ (32 - prefix)
		start = ((octets[1] * 256 + octets[2]) * 256 + octets[3]) * 256 + octets[4]
		start = start - (start % size)
		finish = start + size - 1
		for (i = 1; i <= protected_count; i++) {
			if (start <= protected_end[i] && finish >= protected_start[i]) { bad("overlaps private, loopback, link-local or shared IPv4 " protected_name[i]); next }
		}
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

if ! mv "${TMP_NEW}" "${THREAT_BLOCKLIST_TARGET}"
then
	echo "nginx_update_threat_blocklist: could not replace ${THREAT_BLOCKLIST_TARGET}; keeping previous blocklist."
	rm -f "${TMP_NEW}"
	return 1
fi
chown nginx:nginx "${THREAT_BLOCKLIST_TARGET}" 2>/dev/null || true
ENTRIES=$(grep -cvE '^[[:space:]]*(#|$)' "${THREAT_BLOCKLIST_TARGET}")
echo "nginx_update_threat_blocklist: blocklist updated (${ENTRIES} entries). Should reload."
return 0
