#!/bin/bash

# Behavioural tests for the pg (PgBouncer) image: LDAP search+bind through the HBA file
# pgbouncer_init generates, the rejected-user list, client TLS, the admin console (and the
# RELOAD the Nomad template runs), several processes, and a bind password that needs
# quoting. They run on the host with docker, on a private network: a throwaway OpenLDAP
# (slapd on Alpine), a PostgreSQL, the image under test and a psql client. PostgreSQL asks
# for scram-sha-256 and database.ini carries no password= (as in production), so a login
# only succeeds if PgBouncer hands the client's LDAP password on to the server.
#
#   docker build -t distributor-pg-test src/main/infrastructure/pg
#   src/test/infrastructure/pg/pgbouncer_test.sh distributor-pg-test
#
# EXPECT_VERSION=1.26.1 also checks the version the admin console reports; EXPECT_HBA=false
# runs it against a PAM image, skipping the HBA-only checks. Passwords are
# generated per run. Needs network access once, to install slapd and pull postgres.
# Exits non-zero when any test fails.

set -u
IMAGE=${1:?usage: pgbouncer_test.sh <image>}
EXPECT_VERSION=${EXPECT_VERSION:-}
# The HBA-only checks are expected to run; EXPECT_HBA=false (a run against the PAM image)
# is the only way to skip them.
EXPECT_HBA=${EXPECT_HBA:-true}
ALPINE=alpine:3.24.3
POSTGRES=postgres:18.6-alpine3.24
P=pgbtest-$$
PASSED=0
FAILED=0
SKIPPED=0
TMP=$(mktemp -d)
cleanup() {
	docker rm -f "$P-ldap" "$P-pg" "$P-client" "$P-b1" "$P-b2" "$P-b3" "$P-b4" "$P-b5" "$P-b6" "$P-b7" "$P-b8" "$P-b9" "$P-b10" "$P-b11" "$P-b12" "$P-b13" "$P-b14" "$P-b15" "$P-b16" "$P-b17" >/dev/null 2>&1
	docker network rm "$P" >/dev/null 2>&1
	rm -rf "$TMP"
}
trap cleanup EXIT
pass() { PASSED=$((PASSED + 1)); echo "PASS: $1"; }
fail() { FAILED=$((FAILED + 1)); echo "FAIL: $1${2:+ ($2)}"; }
skip() { SKIPPED=$((SKIPPED + 1)); echo "SKIP: $1"; }
check() { local name=$1 detail=$2; shift 2; if "$@"; then pass "$name"; else fail "$name" "$detail"; fi; } # <name> <detail> <test...>
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
rand() { head -c 18 /dev/urandom | base64 | tr -d '/+='; }

BASE_DN="dc=test,dc=local"
BIND_DN="cn=reader,ou=services,$BASE_DN"
BIND_PW=$(rand)
ODD_BIND_DN="cn=reader2,ou=services,$BASE_DN"
ODD_BIND_PW="$(rand) \"q\"#, x\\c\\"
ALICE_PW=$(rand)
BOB_PW=$(rand)
CAROL_PW=$(rand)
EVE_PW=$(rand)
DW_PW=$(rand)
MON_PW=$(rand)

# Directory: posix users alice, datawarehouse, database.monitor and carol (whose uid is not her
# cn, so only a cn match lets her in); eve is blocked the way service-auth blocks a user
# (businessCategory=BLOCKED); bob has a uid but no posixAccount. Only a bound user can
# search, so a lost bind DN or password fails the logins.
posix_user() { # <cn> <uid number> <password> [uid]
	printf 'dn: cn=%s,ou=people,%s\nobjectClass: inetOrgPerson\nobjectClass: posixAccount\n' "$1" "$BASE_DN"
	printf 'cn: %s\nsn: %s\nuid: %s\nuidNumber: %s\ngidNumber: %s\nhomeDirectory: /home/%s\nuserPassword: %s\n\n' \
		"$1" "$1" "${4:-$1}" "$2" "$2" "$1" "$3"
}
{
	printf 'dn: %s\nobjectClass: dcObject\nobjectClass: organization\no: test\ndc: test\n\n' "$BASE_DN"
	printf 'dn: ou=people,%s\nobjectClass: organizationalUnit\nou: people\n\n' "$BASE_DN"
	printf 'dn: ou=services,%s\nobjectClass: organizationalUnit\nou: services\n\n' "$BASE_DN"
	printf 'dn: %s\nobjectClass: person\ncn: reader\nsn: reader\nuserPassword: %s\n\n' "$BIND_DN" "$BIND_PW"
	printf 'dn: %s\nobjectClass: person\ncn: reader2\nsn: reader2\nuserPassword: %s\n\n' "$ODD_BIND_DN" "$ODD_BIND_PW"
	posix_user alice 10001 "$ALICE_PW"
	posix_user datawarehouse 10002 "$DW_PW"
	posix_user database.monitor 10003 "$MON_PW"
	posix_user carol 10004 "$CAROL_PW" c.arol
	posix_user eve 10005 "$EVE_PW" | sed 's/^uid: eve$/uid: eve\nbusinessCategory: BLOCKED/'
	printf 'dn: cn=bob,ou=people,%s\nobjectClass: inetOrgPerson\ncn: bob\nsn: bob\nuid: bob\nuserPassword: %s\n\n' "$BASE_DN" "$BOB_PW"
} > "$TMP/seed.ldif"
cat > "$TMP/slapd.conf" <<EOF
include /etc/openldap/schema/core.schema
include /etc/openldap/schema/cosine.schema
include /etc/openldap/schema/inetorgperson.schema
include /etc/openldap/schema/nis.schema
modulepath /usr/lib/openldap
moduleload back_mdb.so
pidfile /run/openldap/slapd.pid
TLSCACertificateFile /tls/ca.crt
TLSCertificateFile /tls/srv.crt
TLSCertificateKeyFile /tls/srv.key
database mdb
directory /var/lib/openldap/test
suffix "$BASE_DN"
access to attrs=userPassword by self read by anonymous auth by * none
access to * by users read by anonymous auth by * none
EOF
mkdir "$TMP/database"
printf 'appdb = host=%s-pg port=5432 dbname=appdb\n' "$P" > "$TMP/database/database.ini"

# slapd serves ldap:// (with StartTLS) and ldaps://, with a certificate for its container
# name signed by a throwaway CA.
cat > "$TMP/ldap.sh" <<'EOF'
apk add -q --no-cache openldap openldap-back-mdb openssl >/dev/null || exit 2
mkdir -p /var/lib/openldap/test /run/openldap /tls && cd /tls || exit 2
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 1 -subj /CN=test-ca 2>/dev/null
openssl req -newkey rsa:2048 -nodes -keyout srv.key -out srv.csr -subj "/CN=$LDAP_HOST" 2>/dev/null
printf 'subjectAltName=DNS:%s\n' "$LDAP_HOST" > ext.cnf
openssl x509 -req -in srv.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out srv.crt -days 1 -extfile ext.cnf 2>/dev/null
slapadd -q -f /slapd.conf -l /seed.ldif && exec slapd -d 256 -f /slapd.conf -h "ldap:/// ldaps:///"
EOF
docker network create "$P" >/dev/null || exit 2
docker create --name "$P-ldap" --network "$P" -e LDAP_HOST="$P-ldap" "$ALPINE" sh /ldap.sh >/dev/null || exit 2
for f in slapd.conf seed.ldif ldap.sh; do docker cp "$TMP/$f" "$P-ldap:/$f" || exit 2; done
docker start "$P-ldap" >/dev/null || exit 2
docker run -d --name "$P-pg" --network "$P" -e POSTGRES_PASSWORD="$(rand)" -e POSTGRES_HOST_AUTH_METHOD=scram-sha-256 \
	"$POSTGRES" >/dev/null || exit 2
docker run -d --name "$P-client" --network "$P" --entrypoint sleep "$POSTGRES" infinity >/dev/null || exit 2

wait_for() { # <seconds> <command...>
	local n=$1; shift
	while [ "$n" -gt 0 ]; do "$@" >/dev/null 2>&1 && return 0; sleep 1; n=$((n - 1)); done
	return 1
}
wait_for 120 sh -c "docker logs $P-ldap 2>&1 | grep -q 'slapd starting'" || { echo "slapd did not start"; docker logs "$P-ldap" 2>&1 | tail -5; exit 2; }
docker cp "$P-ldap:/tls/ca.crt" "$TMP/ca.crt" || exit 2
wait_for 60 docker exec "$P-pg" pg_isready -U postgres -h localhost || { echo "postgres did not start"; exit 2; }
docker exec "$P-pg" psql -qU postgres -c "CREATE DATABASE appdb" -c "CREATE ROLE alice LOGIN PASSWORD '$ALICE_PW'" \
	-c "CREATE ROLE datawarehouse LOGIN PASSWORD '$DW_PW'" -c "CREATE ROLE bob LOGIN PASSWORD '$BOB_PW'" \
	-c "CREATE ROLE ghost LOGIN PASSWORD '$BOB_PW'" -c "CREATE ROLE carol LOGIN PASSWORD '$CAROL_PW'" \
	-c "CREATE ROLE eve LOGIN PASSWORD '$EVE_PW'" -c "CREATE ROLE \"DataWarehouse\" LOGIN PASSWORD '$DW_PW'" \
	-c "CREATE ROLE \"al*\" LOGIN PASSWORD '$ALICE_PW'" -c "CREATE ROLE \"eve)(|(cn=eve\" LOGIN PASSWORD '$EVE_PW'" \
	>/dev/null || exit 2

# Starts a PgBouncer from the image under test: <name> <bind dn> <bind password> [docker run args].
bouncer() {
	local name=$1 dn=$2 pw=$3; shift 3
	docker create --name "$name" --network "$P" \
		-e CERT_C=BR -e CERT_ST=SP -e CERT_L=SP -e CERT_O=test -e CERT_OU=test -e CERT_CN="$name" \
		-e LDAP_URI="$P-ldap" -e LDAP_PORT=389 -e LDAP_BASE_DN="$BASE_DN" -e LDAP_USER="$dn" -e LDAP_PASSWORD="$pw" \
		-e REJECT_USERS=datawarehouse "$@" "$IMAGE" >/dev/null || return 1
	docker cp "$TMP/database" "$name:/etc/pgbouncer/database" || return 1
	docker cp "$TMP/ca.crt" "$name:/tmp/ldap-ca.crt" || return 1
	docker start "$name" >/dev/null || return 1
	wait_for 60 sh -c "docker logs $name 2>&1 | grep -q 'process up'"
}
# psql through a bouncer: <bouncer> <user> <password> <sslmode> <database> <sql>.
q() { docker exec -e PGPASSWORD="$3" -e PGSSLMODE="$4" -e PGCONNECT_TIMEOUT=10 "$P-client" psql -h "$1" -U "$2" -d "$5" -tAc "$6" 2>&1; }

# The first PgBouncer sets the filter explicitly, as a deployment may; the second one runs
# the image default. Both refuse users service-auth blocked.
PROD_FILTER='(&(objectClass=posixAccount)(cn=$username)(!(businessCategory=BLOCKED)))'
bouncer "$P-b1" "$BIND_DN" "$BIND_PW" -e LDAP_SEARCH_FILTER="$PROD_FILTER" || { echo "PgBouncer did not start"; docker logs "$P-b1" 2>&1 | tail -20; exit 2; }
B=$P-b1

OUT=$(q "$B" alice "$ALICE_PW" require appdb "select current_user")
check "an LDAP posixAccount user logs in" "$OUT" [ "$OUT" = alice ]
FILTERS=$(docker logs "$P-ldap" 2>&1 | grep -o 'filter="[^"]*alice[^"]*"' | sort -u | tr '\n' ' ')
posix_cn_search() { has "$FILTERS" '(objectClass=posixAccount)' && has "$FILTERS" '(cn=alice)'; }
check "LDAP was searched with the posixAccount filter on cn" "${FILTERS:-no search}" posix_cn_search
OUT=$(q "$B" carol "$CAROL_PW" require appdb "select current_user")
check "a user is matched by cn, not uid" "$OUT" [ "$OUT" = carol ]
OUT=$(q "$B" alice "$ALICE_PW-x" require appdb "select 1")
check "a wrong password is refused" "$OUT" [ "$OUT" != 1 ]
OUT=$(q "$B" bob "$BOB_PW" require appdb "select 1")
check "a user without posixAccount is refused" "$OUT" [ "$OUT" != 1 ]
OUT=$(q "$B" ghost "$BOB_PW" require appdb "select 1")
check "a user missing from LDAP is refused" "$OUT" [ "$OUT" != 1 ]
OUT=$(q "$B" datawarehouse "$DW_PW" require appdb "select 1")
check "a rejected user is refused even with the right password" "$OUT" [ "$OUT" != 1 ]
# A search for datawarehouse would match (cn=datawarehouse); the (!(cn=datawarehouse)) every
# search now carries does not count.
ASKED=$(docker logs "$P-ldap" 2>&1 | grep -o 'filter="[^"]*"' | sed 's/(!(cn=datawarehouse))//g' | grep -c "cn=datawarehouse")
check "and LDAP is never asked about it" "$ASKED searches" [ "$ASKED" = 0 ]
OUT=$(q "$B" DataWarehouse "$DW_PW" require appdb "select 1")
check "another spelling of a rejected user is refused (it has a role too)" "$OUT" [ "$OUT" != 1 ]
OUT=$(q "$B" eve "$EVE_PW" require appdb "select 1")
check "a user blocked in service-auth (businessCategory=BLOCKED) is refused" "$OUT" [ "$OUT" != 1 ]
# "al*" would make (cn=al*) find alice; PgBouncer must refuse the name before searching.
OUT=$(q "$B" 'al*' "$ALICE_PW" require appdb "select 1")
check "a user name with filter characters (al*) is refused (it has a role too)" "$OUT" [ "$OUT" != 1 ]
# "eve)(|(cn=eve" would OR away the BLOCKED clause and let eve in.
OUT=$(q "$B" 'eve)(|(cn=eve' "$EVE_PW" require appdb "select 1")
check "a user name that reshapes the filter (eve)(|(cn=eve) is refused (it has a role too)" "$OUT" [ "$OUT" != 1 ]
RESHAPED=$(docker logs "$P-ldap" 2>&1 | grep -c '(|(cn=eve)')
check "and no search ever carried the reshaped filter" "$RESHAPED searches" [ "$RESHAPED" = 0 ]
OUT=$(q "$B" alice "$ALICE_PW" disable appdb "select 1")
check "a client without TLS is refused" "$OUT" [ "$OUT" != 1 ]
OUT=$(q "$B" database.monitor "$MON_PW" require pgbouncer "show version")
check "the admin console answers database.monitor" "$OUT" has "$OUT" PgBouncer
if [ -n "$EXPECT_VERSION" ]; then
	check "it reports PgBouncer $EXPECT_VERSION" "$OUT" has "$OUT" "PgBouncer $EXPECT_VERSION"
fi
OUT=$(docker exec -e PGPASSWORD="$MON_PW" "$B" sh -c 'psql -h localhost -p 5432 -c "RELOAD;" -U database.monitor pgbouncer' 2>&1)
check "RELOAD from inside the container (the Nomad template's change script) works" "$OUT" [ "$OUT" = RELOAD ]
OUT=$(q "$B" alice "$ALICE_PW" require appdb "select current_user")
check "and logins still work after it" "$OUT" [ "$OUT" = alice ]
# The HBA checks only apply to an image that authenticates through the HBA file.
HBA=false
docker exec "$B" sh -c 'grep -Eq "^auth_type[[:space:]]*=[[:space:]]*hba" /etc/pgbouncer/pgbouncer0.ini' && HBA=true
if [ "$EXPECT_HBA" = true ] && ! $HBA; then
	fail "the image authenticates through the HBA file (auth_type = hba)" "set EXPECT_HBA=false for a PAM image"
fi
if $HBA; then
	MODE=$(docker exec "$B" sh -c 'stat -c "%a %U" /etc/pgbouncer/pgbouncer_hba.conf')
	check "the HBA file (it holds the bind password) is 600 and owned by postgres" "$MODE" [ "$MODE" = "600 postgres" ]
else
	skip "the HBA file is 600 and owned by postgres (EXPECT_HBA=false)"
fi

bouncer "$P-b2" "$ODD_BIND_DN" "$ODD_BIND_PW" -e PROCESSES=2 || fail "a second PgBouncer (odd bind password, 2 processes) starts"
OUT=$(q "$P-b2" alice "$ALICE_PW" require appdb "select current_user")
check "a bind password with quotes, a hash, a comma, spaces and backslashes works" "$OUT" [ "$OUT" = alice ]
OUT=$(q "$P-b2" eve "$EVE_PW" require appdb "select 1")
check "the image default filter also refuses a user blocked in service-auth" "$OUT" [ "$OUT" != 1 ]
N=$(docker exec "$P-b2" sh -c 'cat /proc/[0-9]*/comm 2>/dev/null | grep -cx pgbouncer')
check "PROCESSES=2 runs two PgBouncer processes" "$N" [ "$N" = 2 ]
OK=0
for _ in 1 2 3 4 5 6 7 8; do [ "$(q "$P-b2" alice "$ALICE_PW" require appdb "select 1")" = 1 ] && OK=$((OK + 1)); done
check "and every login across them succeeds" "$OK/8" [ "$OK" = 8 ]

# Starts a container that must refuse to boot: <name> <case> <expected message> [docker run args].
refuses_to_boot() {
	local name=$1 case=$2 message=$3 rc says; shift 3
	docker run -d --name "$name" --network "$P" -e CERT_CN=x "$@" "$IMAGE" >/dev/null
	wait_for 30 sh -c "[ \"\$(docker inspect -f '{{.State.Running}}' $name)\" = false ]"
	rc=$(docker inspect -f '{{.State.ExitCode}}' "$name")
	says=$(docker logs "$name" 2>&1 | grep -c "$message")
	check "$case, the container exits non-zero" "rc=$rc" [ "$rc" != 0 ]
	check "and says why" "$says" [ "$says" != 0 ]
}
if $HBA; then
	refuses_to_boot "$P-b3" "without LDAP_URI" "must be set"
	refuses_to_boot "$P-b4" "without LDAP_BASE_DN" "must be set" -e LDAP_URI="$P-ldap"
	# Twelve 15-character names: the options fit in 1024 bytes, the filter not in 256.
	refuses_to_boot "$P-b5" "with a search filter PgBouncer would cut" "PgBouncer takes 255" \
		-e LDAP_URI="$P-ldap" -e LDAP_BASE_DN="$BASE_DN" \
		-e REJECT_USERS="$(printf 'service-user-%02d,' 1 2 3 4 5 6 7 8 9 10 11 12)"
	# Five 12-letter accented names: they fit in 256 characters, not in 256 bytes.
	refuses_to_boot "$P-b17" "with a search filter that fits in characters but not in bytes" "PgBouncer takes 255" \
		-e LDAP_URI="$P-ldap" -e LDAP_BASE_DN="$BASE_DN" \
		-e REJECT_USERS="$(printf '\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251\303\251%s,' 1 2 3 4 5)"
	refuses_to_boot "$P-b6" "with a search filter without \$username" "must contain" \
		-e LDAP_URI="$P-ldap" -e LDAP_BASE_DN="$BASE_DN" -e LDAP_SEARCH_FILTER="(objectClass=posixAccount)"
	refuses_to_boot "$P-b8" "with a line break in LDAP_PASSWORD" "must be a single line" \
		-e LDAP_URI="$P-ldap" -e LDAP_BASE_DN="$BASE_DN" -e LDAP_PASSWORD="$(printf 'x\nhost all all all trust')"
	refuses_to_boot "$P-b9" "with REJECT_USERS and no (attribute=\$username) to exclude them on" "needs a filter" \
		-e LDAP_URI="$P-ldap" -e LDAP_BASE_DN="$BASE_DN" -e REJECT_USERS=datawarehouse \
		-e LDAP_SEARCH_FILTER='(mail=$username@test.local)'
	# A bare filter, as pam_filter was written, still works once the rejected users are ANDed in.
	bouncer "$P-b7" "$BIND_DN" "$BIND_PW" -e LDAP_SEARCH_FILTER='cn=$username' || fail "a PgBouncer with a bare filter starts"
	OUT=$(q "$P-b7" alice "$ALICE_PW" require appdb "select current_user")
	check "a bare filter (cn=\$username without parentheses) with REJECT_USERS still logs in" "$OUT" [ "$OUT" = alice ]
	OUT=$(q "$P-b7" DataWarehouse "$DW_PW" require appdb "select 1")
	check "and still leaves the rejected user out in another spelling" "$OUT" [ "$OUT" != 1 ]
	# TLS to LDAP, opt-in: ldaps on 636, StartTLS on 389, and a CA the server cert must chain to.
	bouncer "$P-b10" "$BIND_DN" "$BIND_PW" -e LDAP_SCHEME=ldaps -e LDAP_PORT=636 -e LDAPTLS_CACERT=/tmp/ldap-ca.crt \
		|| fail "a PgBouncer on ldaps starts"
	OUT=$(q "$P-b10" alice "$ALICE_PW" require appdb "select current_user")
	check "LDAP_SCHEME=ldaps (port 636, CA in LDAPTLS_CACERT) logs in" "$OUT" [ "$OUT" = alice ]
	bouncer "$P-b11" "$BIND_DN" "$BIND_PW" -e LDAP_TLS=1 -e LDAPTLS_CACERT=/tmp/ldap-ca.crt || fail "a PgBouncer on StartTLS starts"
	OUT=$(q "$P-b11" alice "$ALICE_PW" require appdb "select current_user")
	check "LDAP_TLS=1 (StartTLS on 389) logs in" "$OUT" [ "$OUT" = alice ]
	STARTTLS=$(docker logs "$P-ldap" 2>&1 | grep -c 'EXT oid=1.3.6.1.4.1.1466.20037')
	check "and slapd saw the StartTLS request" "$STARTTLS" [ "$STARTTLS" != 0 ]
	bouncer "$P-b12" "$BIND_DN" "$BIND_PW" -e LDAP_SCHEME=ldaps -e LDAP_PORT=636 || fail "a PgBouncer on ldaps without the CA starts"
	OUT=$(q "$P-b12" alice "$ALICE_PW" require appdb "select 1")
	check "ldaps without the server's CA is refused (the certificate is verified)" "$OUT" [ "$OUT" != 1 ]
	refuses_to_boot "$P-b13" "with LDAP_TLS=yes" "LDAP_TLS must be 0 or 1" \
		-e LDAP_URI="$P-ldap" -e LDAP_BASE_DN="$BASE_DN" -e LDAP_TLS=yes
	refuses_to_boot "$P-b14" "with LDAP_SCHEME=ldaps on port 389" "needs the ldaps port" \
		-e LDAP_URI="$P-ldap" -e LDAP_BASE_DN="$BASE_DN" -e LDAP_SCHEME=ldaps
	refuses_to_boot "$P-b15" "with LDAP_SCHEME=ldaps and LDAP_TLS=1" "already TLS" \
		-e LDAP_URI="$P-ldap" -e LDAP_BASE_DN="$BASE_DN" -e LDAP_SCHEME=ldaps -e LDAP_PORT=636 -e LDAP_TLS=1
	refuses_to_boot "$P-b16" "with LDAPTLS_REQCERT=never" "turn off the LDAP server certificate check" \
		-e LDAP_URI="$P-ldap" -e LDAP_BASE_DN="$BASE_DN" -e LDAPTLS_REQCERT=never
else
	skip "the boot refusals, the bare filter and the LDAP TLS checks (EXPECT_HBA=false)"
fi

echo "$PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" = 0 ]
