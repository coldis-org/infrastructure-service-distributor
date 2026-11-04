#!/bin/bash

# Behavioural tests for nginx_update_threat_blocklist and the threat-blocklist
# snippets. They run inside the nginx image, against the script and conf.d files
# it installs, with a throwaway nginx serving the lists (plain http, TLS signed by
# a throwaway CA, a 1-byte/s endpoint) and the geo/403 path itself:
#
#   docker build -t distributor-nginx-test src/main/infrastructure/nginx
#   docker run --rm --entrypoint bash -v "$PWD/src/test/infrastructure/nginx:/test:ro" \
#     distributor-nginx-test /test/threat_blocklist_test.sh
#
# The container's nginx.conf is replaced with a minimal one; the image's own is
# not used. Needs network access once, to install openssl if the image lacks it.
# Exits non-zero when any test fails.

# Variables used only inside the strings check evaluates look unused to shellcheck.
# shellcheck disable=SC2034
set -u
if ! command -v openssl >/dev/null || [ ! -d /usr/local/share/ca-certificates ]
then
	apt-get -qq update >/dev/null 2>&1 && apt-get -qq install -y openssl ca-certificates >/dev/null 2>&1 \
		|| { echo "cannot install openssl/ca-certificates"; exit 2; }
fi
command -v nginx_update_threat_blocklist >/dev/null || { echo "nginx_update_threat_blocklist is not installed in this image"; exit 2; }

# A throwaway CA trusted by the system store, and a server cert for 127.0.0.1.
mkdir -p /tls && cd /tls || exit 2
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 1 -subj "/CN=test-ca" >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -keyout srv.key -out srv.csr -subj "/CN=127.0.0.1" >/dev/null 2>&1
printf 'subjectAltName=IP:127.0.0.1\n' > ext.cnf
openssl x509 -req -in srv.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out srv.crt -days 1 -extfile ext.cnf >/dev/null 2>&1
cp ca.crt /usr/local/share/ca-certificates/test-ca.crt && update-ca-certificates >/dev/null 2>&1
cd / || exit 2

T=/etc/nginx/conf.d/include.d/threat-blocklist-ips.conf
mkdir -p /srv/f
fixture() { mkdir -p "/srv/f/$1"; printf "$2" > "/srv/f/$1/blocklist"; }
fixture valid '# list\n203.0.113.0/24 1;\n198.51.100.7 1;\n2001:db8::/32 1;\n'
fixture blanket '203.0.113.0/24 1;\n0.0.0.0/0 1;\n'
fixture private10 '10.0.0.0/8 1;\n'
fixture localnet '172.16.5.0/24 1;\n'
fixture loopback '127.0.0.1 1;\n'
fixture garbage '203.0.113.9 1;\ninclude /etc/passwd;\n'
fixture zerobyte ''
fixture blank '\n\r\n   \n'
fixture explicit_empty '# empty\n'
fixture super172 '172.0.0.0/8 1;\n'
fixture super192 '192.0.0.0/8 1;\n'
fixture super172_11 '172.0.0.0/11 1;\n'
fixture v6zero '0::/16 1;\n'
fixture v6mapped '::ffff:10.0.0.0/104 1;\n'
fixture v6double 'dead::beef::1 1;\n'
fixture v6triple '::: 1;\n'
fixture v6short '1:2 1;\n'
fixture v6long '12345:: 1;\n'
fixture v6trailing '1:2:3:4:5:6:7:: 1;\n'
fixture octet_prefix '203.0.113.0/33 1;\n'
fixture v6full '2001:0db8:0000:0000:0000:ff00:0042:8329 1;\n'
fixture v6trailing_ok '2001:db8:1:2:3:4:: 1;\n'
fixture indented '    203.0.113.0/24 1;   # scanner\n\t198.51.100.7 1;\n2001:db8::/32 1; # reason\n'
fixture stamped '# generated 2026-11-03T10:01:00Z\n203.0.113.0/24 1;\n198.51.100.7 1;\n2001:db8::/32 1;\n'
fixture public8 '45.0.0.0/8 1;\n203.0.113.0/24 1;\n'
fixture auth '198.51.100.0/24 1;\n'
printf '192.0.2.0/24 1;\n' > /srv/f/blocklist
mkdir -p /srv/f/api/v1; printf '203.0.113.0/24 1;\n198.51.100.7 1;\n2001:db8::/32 1;\n# path\n' > /srv/f/api/v1/threats
mkdir -p /srv/f/slow; head -c 4096 /dev/zero | tr '\0' '#' > /srv/f/slow/blocklist

cat > /etc/nginx/nginx.conf <<'EOF'
events {}
http {
  include /etc/nginx/conf.d/http.d/threat-blocklist-geo.conf;
  server { listen 8081; root /srv/f;
    location /slow/ { limit_rate 1; }
  }
  server { listen 8443 ssl; root /srv/f; ssl_certificate /tls/srv.crt; ssl_certificate_key /tls/srv.key;
    location /auth/ { if ($http_authorization != "Bearer t0k3n") { return 401; } }
    location /redir/ { return 302 http://127.0.0.1:8081/valid/blocklist; }
  }
  server { listen 8080; include /etc/nginx/conf.d/include.d/threat-blocklist.conf; location / { return 200 "ok\n"; } }
}
EOF
nginx -t -q && nginx || { echo "test nginx failed to start"; exit 2; }

pass=0; fail=0
check() { if eval "$2"; then pass=$((pass+1)); echo "PASS: $1"; else fail=$((fail+1)); echo "FAIL: $1"; fi; }
pull() { THREAT_BLOCKLIST_URL="http://127.0.0.1:8081/$1/blocklist" nginx_update_threat_blocklist >/tmp/out 2>&1; RC=$?; }
run() { env "$@" nginx_update_threat_blocklist >/tmp/out 2>&1; RC=$?; }
entries() { grep -cvE '^[[:space:]]*(#|$)' "$T"; }
status() { wget -q -O /dev/null -S "http://127.0.0.1:8080/" 2>&1 | awk '/HTTP\//{print $2}' | tail -1; }

# Valid lists and what counts as a change.
pull valid;          check "a valid list is written (rc 0, 3 entries)"                  '[ $RC = 0 ] && [ "$(entries)" = 3 ]'
check "nginx -t accepts the written list"                                             'nginx -t -q 2>/dev/null'
pull valid;          check "an unchanged list does not ask for a reload (rc 1)"         '[ $RC = 1 ]'
pull indented;       check "indented entries and inline comments are the same entries"  '[ $RC = 1 ] && [ "$(entries)" = 3 ]'
pull stamped;        check "a new comment (timestamp) alone does not reload"            '[ $RC = 1 ]'

# URL handling.
run THREAT_BLOCKLIST_URL="http://127.0.0.1:8081/api/v1/threats"
check "a URL with a path is used as configured"                                       '[ $RC = 1 ] && ! grep -q "failed" /tmp/out'
run THREAT_BLOCKLIST_URL="http://127.0.0.1:8081/"
check "a host:port/ URL gets /blocklist appended"                                     '[ $RC = 0 ] && [ "$(entries)" = 1 ]'
pull valid
run THREAT_BLOCKLIST_TIMEOUT=10s THREAT_BLOCKLIST_URL="http://127.0.0.1:8081/valid/blocklist"
check "a timeout with a unit (10s) works"                                             '[ $RC = 1 ] && ! grep -qi "arithmetic\|error" /tmp/out'

# Refused lists keep the previous one.
for c in blanket private10 localnet loopback garbage zerobyte blank missing super172 super192 super172_11 \
	v6zero v6mapped v6double v6triple v6short v6long v6trailing octet_prefix
do
	pull "$c"; check "list '$c' is refused and the previous list kept" '[ $RC = 1 ] && [ "$(entries)" = 3 ]'
done
START=$(date +%s); run THREAT_BLOCKLIST_TIMEOUT=2 THREAT_BLOCKLIST_URL="http://127.0.0.1:8081/slow/blocklist"; ELAPSED=$(( $(date +%s) - START ))
check "a trickling service is cut off by the overall limit"                           '[ $RC = 1 ] && [ $ELAPSED -le 8 ] && [ "$(entries)" = 3 ]'
bash /usr/bin/nginx_update_threat_blocklist >/tmp/outb 2>&1
check "under bash, an unset URL does not fetch"                                       '! grep -q "pull of" /tmp/outb && ! grep -qi "return" /tmp/outb'

# The token: https only, never across redirects, never left on disk.
pull valid
run THREAT_BLOCKLIST_TOKEN=t0k3n THREAT_BLOCKLIST_URL="http://127.0.0.1:8081/auth/blocklist"
check "a token with an http URL is not sent"                                          '[ $RC = 1 ] && [ "$(entries)" = 3 ] && grep -q "not https" /tmp/out'
run THREAT_BLOCKLIST_TOKEN=t0k3n THREAT_BLOCKLIST_URL="127.0.0.1:8443"
check "a token with a bare host:port (http to wget) is not sent"                      '[ $RC = 1 ] && [ "$(entries)" = 3 ] && grep -q "not https" /tmp/out'
run THREAT_BLOCKLIST_URL="https://127.0.0.1:8443/auth/blocklist"
check "https without the token gets 401, previous list kept"                          '[ $RC = 1 ] && [ "$(entries)" = 3 ]'
run THREAT_BLOCKLIST_TOKEN=t0k3n THREAT_BLOCKLIST_URL="https://127.0.0.1:8443/auth/blocklist"
check "https with the token pulls the list"                                           '[ $RC = 0 ] && [ "$(entries)" = 1 ]'
pull valid
run THREAT_BLOCKLIST_TOKEN=t0k3n THREAT_BLOCKLIST_URL="https://127.0.0.1:8443/redir/blocklist"
check "a redirect is not followed with the token"                                     '[ $RC = 1 ] && [ "$(entries)" = 3 ]'
pull auth;           check "http without a token still works"                            '[ $RC = 0 ] && [ "$(entries)" = 1 ]'
check "no token file is left behind"                                                  '[ -z "$(grep -l "Bearer" /tmp/tmp.* 2>/dev/null)" ]'

# Accepted forms.
pull v6trailing_ok;  check "a trailing :: standing for two groups is accepted"        '[ $RC = 0 ] && [ "$(entries)" = 1 ]'
pull v6full;         check "a full-form public IPv6 is accepted"                       '[ $RC = 0 ] && [ "$(entries)" = 1 ] && nginx -t -q 2>/dev/null'
pull public8;        check "a public /8 is accepted"                                    '[ $RC = 0 ] && [ "$(entries)" = 2 ]'
check "no .new temp file is left beside the target"                                   '! ls /etc/nginx/conf.d/include.d/*.new >/dev/null 2>&1'

# Empty lists and switching off.
pull explicit_empty; check "a comment-only body clears the list"                        '[ $RC = 0 ] && [ "$(entries)" = 0 ]'
run THREAT_BLOCKLIST_URL=;  check "an unset URL with an empty list skips (rc 1)"        '[ $RC = 1 ]'
pull valid
run THREAT_BLOCKLIST_URL=;  check "unsetting the URL clears a list in place (rc 0)"     '[ $RC = 0 ] && [ "$(entries)" = 0 ]'
run THREAT_BLOCKLIST_URL=;  check "and the next run with no URL does not reload again" '[ $RC = 1 ]'

# The block itself: a listed source gets 403, an empty list lets it through.
printf '127.0.0.1 1;\n' > "$T"; nginx -s reload; sleep 1
check "a listed source is answered 403"                                               '[ "$(status)" = 403 ]'
printf '# empty\n' > "$T"; nginx -s reload; sleep 1
check "with an empty list the same source gets 200"                                   '[ "$(status)" = 200 ]'

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
