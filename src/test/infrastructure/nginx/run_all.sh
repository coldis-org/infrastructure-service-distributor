#!/usr/bin/env bash
#
# Builds the Debian (current) and Alpine variants of the nginx and nginx-config images, runs
# smoke_test.sh against both in parallel and compares them. The Debian run is the baseline:
# a check failing only on Alpine is a regression; one failing on both is pre-existing.
#
# Usage: run_all.sh [--no-build]
# Output: target/smoke/{debian,alpine}/ (results.tsv, logs) and target/smoke/report.md.
# Exits 1 if Alpine has regressions.

set -u

ROOT=$( cd "$( dirname "$0" )/../../../.." && pwd )
INFRA=${ROOT}/src/main/infrastructure
TEST_DIR=${ROOT}/src/test/infrastructure/nginx
OUT=${ROOT}/target/smoke
VARIANTS="debian alpine"
BUILD=true
[ "${1:-}" = "--no-build" ] && BUILD=false

mkdir -p "${OUT}"

# Builds the images.
if ${BUILD}
then
	for variant in ${VARIANTS}
	do
		dockerfile=Dockerfile
		[ "${variant}" = "alpine" ] && dockerfile=Dockerfile.alpine
		(
			docker build -t "sd-nginx:${variant}" -f "${INFRA}/nginx/${dockerfile}" "${INFRA}/nginx" \
			&& docker build -t "sd-nginx-config:${variant}" --build-arg "BASE_IMAGE=sd-nginx:${variant}" "${INFRA}/nginx-config"
		) > "${OUT}/build-${variant}.log" 2>&1 &
	done
	wait
	for variant in ${VARIANTS}
	do
		docker image inspect "sd-nginx-config:${variant}" >/dev/null 2>&1 \
			|| { echo "Build failed for ${variant}; see ${OUT}/build-${variant}.log"; tail -20 "${OUT}/build-${variant}.log"; exit 2; }
	done
fi

# Runs the smoke tests.
for variant in ${VARIANTS}
do
	rm -rf "${OUT:?}/${variant}"
	"${TEST_DIR}/smoke_test.sh" "sd-nginx:${variant}" "sd-nginx-config:${variant}" "${OUT}/${variant}" \
		> "${OUT}/smoke-${variant}.log" 2>&1 &
done
wait

# Compares the results.
REPORT=${OUT}/report.md
status_of() { awk -F'\t' -v c="$2" '$2 == c { print $1 }' "${OUT}/$1/results.tsv"; }
REGRESSIONS=0
{
	echo "# Alpine vs Debian smoke test"
	echo
	echo "| Check | Debian | Alpine |"
	echo "|---|---|---|"
	cut -f2 "${OUT}/debian/results.tsv" "${OUT}/alpine/results.tsv" | awk '!seen[$0]++' | while read -r name
	do
		d=$( status_of debian "${name}" ); a=$( status_of alpine "${name}" )
		mark=""
		[ "${d}" = "PASS" ] && [ "${a}" != "PASS" ] && mark=" **REGRESSION**"
		echo "| ${name} | ${d:--} | ${a:--}${mark} |"
	done
	echo
	echo "## Failure details"
	echo
	for variant in ${VARIANTS}
	do
		awk -F'\t' -v v="${variant}" '$1 == "FAIL" { print "- " v ": " $2 " — `" $3 "`" }' "${OUT}/${variant}/results.tsv"
	done
	echo
	echo "## Suspicious log lines only on Alpine"
	echo
	echo '```'
	pattern='not found|unrecognized option|invalid option|illegal option|unknown option|applet|syntax error|No such file|cannot|can.t'
	for variant in ${VARIANTS}
	do
		cat "${OUT}/${variant}/edge.log" "${OUT}/${variant}/config.log" 2>/dev/null | grep -Ei "${pattern}" \
			| sed -E 's/[0-9]+/N/g; s/[a-f0-9]{12,}/H/g' | sort -u > "${OUT}/${variant}/suspicious.txt"
	done
	comm -13 "${OUT}/debian/suspicious.txt" "${OUT}/alpine/suspicious.txt"
	echo '```'
	echo
	echo "## Image sizes"
	echo
	for variant in ${VARIANTS}
	do
		echo "- sd-nginx:${variant}: $( docker image inspect -f '{{.Size}}' "sd-nginx:${variant}" | awk '{ printf "%.0f MB", $1/1024/1024 }' )"
	done
} > "${REPORT}"

REGRESSIONS=$( grep -c 'REGRESSION' "${REPORT}" )
cat "${REPORT}"
echo
echo "Report: ${REPORT}"
[ "${REGRESSIONS}" -eq 0 ]
