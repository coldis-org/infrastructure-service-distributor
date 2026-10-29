#!/usr/bin/env bash
#
# Minimal end-to-end flow of the distributor Nginx image: binaries and modules, entrypoint,
# certificates, HTTP/HTTPS/HTTP2, ModSecurity, VTS, syslog/metrics logs, the config scripts
# (add vhost, quarantine of broken files, retest state, cert cleanup, access control, nets),
# and the config sync from a web-config (nginx-config) container, at startup and via cron.
#
# Usage: smoke_test.sh <nginx-image> <nginx-config-image> [out-dir]
# Writes <out-dir>/results.tsv (STATUS<TAB>check<TAB>detail) and the containers' logs.
# Exits 1 if any check fails.

set -u

IMAGE=${1:?nginx image}
CONFIG_IMAGE=${2:?nginx-config image}
OUT=${3:-target/smoke/$(echo "${IMAGE}" | tr '/:' '__')}
ID=$$
NET=sd-smoke-${ID}
EDGE=sd-smoke-edge-${ID}
CFG=sd-smoke-config-${ID}
CFG_HOST=web-config.test
SYNC_TIMEOUT=${SYNC_TIMEOUT:=150}

mkdir -p "${OUT}"
RESULTS=${OUT}/results.tsv
: > "${RESULTS}"
PASSED=0
FAILED=0

log() { echo "[$(date +%T)] ${IMAGE}: $*"; }

# Records a check: check <name> <command...>
check() {
	local name=$1 output
	shift
	if output=$( "$@" 2>&1 )
	then
		PASSED=$(( PASSED + 1 ))
		printf 'PASS\t%s\t\n' "${name}" >> "${RESULTS}"
		log "PASS ${name}"
	else
		FAILED=$(( FAILED + 1 ))
		output=$( echo "${output}" | tr '\n\t' '  ' | cut -c1-300 )
		printf 'FAIL\t%s\t%s\n' "${name}" "${output}" >> "${RESULTS}"
		log "FAIL ${name}: ${output}"
	fi
}

# Retries a command for up to N seconds: wait_for <seconds> <command...>
wait_for() {
	local timeout=$1 i
	shift
	for i in $( seq "${timeout}" )
	do
		"$@" >/dev/null 2>&1 && return 0
		sleep 1
	done
	"$@"
}

in_edge() { docker exec "${EDGE}" sh -c "$1"; }
in_cfg() { docker exec "${CFG}" sh -c "$1"; }
running() { [ "$( docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null )" = "true" ]; }
has_proc() { docker exec "$1" sh -c "cat /proc/[0-9]*/comm 2>/dev/null | grep -qxE '$2'"; }
logs_contain() { docker logs "$1" 2>&1 | grep -qF -- "$2"; }
body_is() { [ "$( curl -s "${@:2}" )" = "$1" ]; }
status_is() { [ "$( curl -s -o /dev/null -w '%{http_code}' "${@:2}" )" = "$1" ]; }

cleanup() {
	docker logs "${EDGE}" > "${OUT}/edge.log" 2>&1
	docker logs "${CFG}" > "${OUT}/config.log" 2>&1
	docker rm -f "${EDGE}" "${CFG}" >/dev/null 2>&1
	docker network rm "${NET}" >/dev/null 2>&1
}
trap cleanup EXIT

# ---------------------------------------------------------------------------------------------
log "Starting web-config (${CONFIG_IMAGE})"
docker network create "${NET}" >/dev/null
# Hostname equals CONF_HOST_NAME so the config container does not sync from itself.
docker run -d --name "${CFG}" --network "${NET}" --network-alias webconfig --hostname "${CFG_HOST}" \
	--memory 512m --cpus 1 -e CONF_HOST_NAME="${CFG_HOST}" -e ENVIRONMENT=test \
	"${CONFIG_IMAGE}" >/dev/null
check "config: container starts and serves /vhost/" \
	wait_for 60 in_cfg "wget -q -O /dev/null --header 'Host: ${CFG_HOST}' http://127.0.0.1/vhost/"
check "config: www-data user exists (nginx_expose_conf)" in_cfg "id www-data"
check "config: self-signed cert has SAN DNS:*.supersim.com.br" \
	in_cfg "openssl x509 -in '/etc/letsencrypt/selfsigned/_.supersim.com.br/cert.pem' -noout -text | grep -q 'DNS:\*.supersim.com.br'"

# Vhost published by web-config before the edge starts (synced by the entrypoint).
in_cfg "printf 'server {\n listen 80;\n server_name synced-a.test;\n location / { return 200 \"synced-a-ok\"; }\n}\n' > /etc/nginx/vhost.d/synced-a.conf"

# ---------------------------------------------------------------------------------------------
log "Starting edge (${IMAGE})"
docker run -d --name "${EDGE}" --network "${NET}" --memory 512m --cpus 1 \
	-p 127.0.0.1::80 -p 127.0.0.1::443 -p 127.0.0.1::9913 \
	-e CONF_HOST_NAME=webconfig -e INTERNAL_SYNC_CONF_HOST_NAME="${CFG_HOST}" -e ENVIRONMENT=test \
	"${IMAGE}" >/dev/null
P80=$( docker port "${EDGE}" 80/tcp | head -1 | sed 's/.*://' )
P443=$( docker port "${EDGE}" 443/tcp | head -1 | sed 's/.*://' )
PVTS=$( docker port "${EDGE}" 9913/tcp | head -1 | sed 's/.*://' )
HTTP=http://127.0.0.1:${P80}
HTTPS=https://127.0.0.1:${P443}

check "startup: edge answers on :80" wait_for 90 status_is 200 "${HTTP}/"
check "startup: container still running" running "${EDGE}"

# Binaries, libraries and tool features the scripts rely on.
check "tools: required binaries present" in_edge '
	missing=; for t in nginx openssl certbot dig envsubst sponge rsyslogd crontab flock wget awk sed grep find diff stat nproc seq expr date
	do command -v $t >/dev/null || missing="$missing $t"; done; [ -z "$missing" ] || { echo "missing:$missing"; exit 1; }'
check "tools: GNU features (grep --include, stat --format %W/%y, wget --recursive)" in_edge '
	grep -r -l --include="*.conf" x /dev/null; [ $? -le 1 ] && stat --format "%W %y" / >/dev/null && wget --help | grep -q -- "--recursive"'
# Only missing libraries count: musl's ldd also lists the ngx_* symbols, resolved from the nginx binary at load time.
check "tools: dynamic modules and libmodsecurity have all libraries" in_edge '
	! ldd /etc/nginx/modules/*.so /usr/local/modsecurity/lib/libmodsecurity.so* 2>&1 | grep -E "=> not found|Error loading shared library"'
check "tools: certbot nginx plugin" in_edge "certbot plugins 2>/dev/null | grep -q '^\* nginx'"
check "tools: timezone America/Sao_Paulo (-03)" in_edge '[ "$(date +%z)" = "-0300" ]'

# Entrypoint results.
check "startup: nginx -t is valid" in_edge "nginx -t"
check "startup: rsyslogd running" has_proc "${EDGE}" "rsyslogd"
check "startup: cron running" has_proc "${EDGE}" "cron|crond"
check "startup: cron jobs installed with schedules substituted" in_edge "crontab -l | grep -q '^\* \* \* \* \* .*nginx_update_all_config'"
check "startup: os_limits read cgroup memory (MAX_MEMORY=512)" logs_contain "${EDGE}" "nginx_tune_opts: [INFO] MAX_MEMORY=512"
check "startup: worker_processes/connections substituted" in_edge "
	grep -Eq '^worker_processes\s+(auto|[0-9]+);' /etc/nginx/nginx.conf && grep -Eq '^\s*worker_connections\s+[0-9]+;' /etc/nginx/nginx.conf"
check "startup: nets generated (access-localnet, networks, access-intranet)" in_edge "
	grep -q 'allow 172.16.0.0/16;' /etc/nginx/conf.d/include.d/access-localnet.conf \
	&& grep -q '172.17.0.0/16' /etc/nginx/conf.d/general.d/networks.conf \
	&& [ -f /etc/nginx/conf.d/include.d/access-intranet.conf ]"
check "startup: dig resolves container DNS" in_edge "dig +short webconfig | grep -Eq '^[0-9.]+$'"

# Certificates.
check "certs: own self-signed cert present with SAN" \
	in_edge "openssl x509 -in '/etc/letsencrypt/selfsigned/_.supersim.com.br/cert.pem' -noout -text | grep -q 'DNS:\*.supersim.com.br'"
check "certs: client cert present" in_edge "[ -s /etc/letsencrypt/selfsigned/client/cert.pem ]"
check "certs: session ticket keys (80 bytes)" in_edge "
	[ \$(wc -c < /etc/letsencrypt/ticket/current.key) -eq 80 ] && [ \$(wc -c < /etc/letsencrypt/ticket/previous.key) -eq 80 ]"
check "certs: dhparam present" in_edge "[ -s /etc/ssl/certs/dhparam.pem ]"

# Traffic.
check "http: GET / serves index.html" sh -c "curl -s '${HTTP}/' | grep -q 'Hello, World!'"
check "https: GET / with TLS" status_is 200 -k "${HTTPS}/"
check "https: HTTP/2 negotiated" sh -c "[ \"\$(curl -sk --http2 -o /dev/null -w '%{http_version}' '${HTTPS}/')\" = 2 ]"
check "https: serves *.supersim.com.br cert" sh -c "curl -skv '${HTTPS}/' -o /dev/null 2>&1 | grep -q 'supersim.com.br'"
check "modsecurity: XSS blocked (403)" status_is 403 -G --data-urlencode 'q=<script>alert(1)</script>' "${HTTP}/"
check "modsecurity: SQLi blocked (403)" status_is 403 -G --data-urlencode "id=1' OR '1'='1' --" "${HTTP}/"
check "vts: prometheus metrics on :9913/status" sh -c "curl -s 'http://127.0.0.1:${PVTS}/status' | grep -q '^nginx_vts_info'"
MISSING_PATH=/smoke-missing-${ID}
check "http: missing file is 404" status_is 404 "${HTTP}${MISSING_PATH}"
check "logs: error_log reaches stderr via rsyslog" wait_for 20 logs_contain "${EDGE}" "${MISSING_PATH}\" failed"

# Scripts.
check "script: nginx_add_vhost + set-misc module (set_md5)" in_edge "
	printf 'server {\nlisten 80;\nserver_name added.test;\nlocation / {\nset_md5 \$h \"abc\";\nreturn 200 \"\$h\";\n}\n}\n' \
	| nginx_add_vhost -v smoke-added -d /etc/nginx/conf.d/vhost.d"
check "script: added vhost served after reload" wait_for 10 body_is 900150983cd24fb0d6963f7d28e17f72 -H 'Host: added.test' "${HTTP}/"

in_edge "echo 'server { listen 80; server_name broken.test; bogus_directive on; }' > /etc/nginx/conf.d/vhost.d/smoke-broken.conf
	echo 'server { listen 443 ssl; server_name badcert.test; ssl_certificate /etc/letsencrypt/live/smoke-none/fullchain.pem; ssl_certificate_key /etc/letsencrypt/live/smoke-none/privkey.pem; }' > /etc/nginx/conf.d/vhost.d/smoke-badcert.conf
	nginx_check_config --no-reload" > "${OUT}/check_config.log" 2>&1
check "script: nginx_check_config quarantines unknown directive" in_edge "[ -f /etc/nginx/conf.d/vhost.d/smoke-broken.conf.err ] && [ ! -f /etc/nginx/conf.d/vhost.d/smoke-broken.conf ]"
check "script: nginx_check_config quarantines missing certificate" in_edge "[ -f /etc/nginx/conf.d/vhost.d/smoke-badcert.conf.err ] && [ ! -f /etc/nginx/conf.d/vhost.d/smoke-badcert.conf ]"
check "script: config valid after quarantine" in_edge "nginx -t"
in_edge "nginx_check_config --no-reload" >> "${OUT}/check_config.log" 2>&1
check "script: retest state recorded and files re-quarantined" in_edge "
	grep -q smoke-broken.conf /etc/nginx/vhost.d/.config_retest_state && grep -q smoke-badcert.conf /etc/nginx/vhost.d/.config_retest_state \
	&& [ -f /etc/nginx/conf.d/vhost.d/smoke-broken.conf.err ] && [ -f /etc/nginx/conf.d/vhost.d/smoke-badcert.conf.err ] && nginx -t"
check "script: nginx -s reload" in_edge "nginx -s reload"
check "script: still serving after reload" wait_for 5 status_is 200 "${HTTP}/"
check "script: nginx_cert_cleanup removes -000N duplicates without errors" in_edge "
	mkdir -p /etc/letsencrypt/live/smoke.test-0001 /etc/letsencrypt/archive/smoke.test-0001 /etc/letsencrypt/live/tmp-smoke
	err=\$(CERT_CLEANUP=true nginx_cert_cleanup 2>&1 >/dev/null); [ -z \"\$err\" ] || { echo \"\$err\"; exit 1; }
	[ ! -e /etc/letsencrypt/live/smoke.test-0001 ] && [ ! -e /etc/letsencrypt/archive/smoke.test-0001 ]"
# The script exits 1 when not in debug (last line is '${DEBUG} && ...'), so its rc is ignored.
check "script: nginx_create_access_control_config (production)" in_edge "
	nginx_create_access_control_config --auth-policies 'developers:developers;admins:admins,ops' --environment production --access-service svc
	f=/etc/nginx/conf.d/include.d/access-identity-management.conf \
	&& grep -q 'location /oauth2/' \$f && grep -q 'allowed_groups=role:admins,role:ops' \$f"
check "script: nginx_create_access_control_config (non production)" in_edge "
	nginx_create_access_control_config --auth-policies 'developers:developers' --environment test
	grep -q 'return 200;' /etc/nginx/conf.d/include.d/access-identity-management.conf"

# Config sync (web-config -> edge).
check "sync: vhost synced at startup" in_edge "[ -f /etc/nginx/vhost.d/synced-a.conf ]"
check "sync: synced vhost served" body_is synced-a-ok -H 'Host: synced-a.test' "${HTTP}/"
check "sync: certs synced from web-config" in_edge "
	[ \"\$(cat /etc/letsencrypt/ticket/current.key | md5sum)\" = \"$( in_cfg 'cat /etc/letsencrypt/ticket/current.key | md5sum' )\" ]"
in_cfg "printf 'server {\n listen 80;\n server_name synced-b.test;\n location / { return 200 \"synced-b-ok\"; }\n}\n' > /etc/nginx/vhost.d/synced-b.conf"
log "Waiting up to ${SYNC_TIMEOUT}s for cron to sync a new vhost"
check "sync: cron syncs and reloads new vhost" wait_for "${SYNC_TIMEOUT}" body_is synced-b-ok -H 'Host: synced-b.test' "${HTTP}/"
check "sync: cron job ran (lock file)" in_edge "[ -f /tmp/nginx_update_all_config.lock ]"
check "logs: metrics access log flushed to stdout" logs_contain "${EDGE}" "\"GET ${MISSING_PATH} HTTP/1.1\""
check "end: edge still running" running "${EDGE}"
check "end: web-config still running" running "${CFG}"

log "Done: ${PASSED} passed, ${FAILED} failed (${RESULTS})"
[ "${FAILED}" -eq 0 ]
