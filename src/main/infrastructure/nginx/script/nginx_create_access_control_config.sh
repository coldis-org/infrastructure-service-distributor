#!/bin/sh -e

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
ACCESS_FILE_DIR="/etc/nginx/conf.d/include.d"
AUTH_POLICIES=""
ENVIRONMENT=""
ACCESS_SERVICE=""

# For each argument.
while :; do
	case ${1} in

		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
			;;

		# Auth policies (routes and roles).
		--auth-policies)
			AUTH_POLICIES=${2}
			shift
			;;

    # Environment.
		--environment)
			ENVIRONMENT=$(printf '%s' "${2}" | tr '[:lower:]' '[:upper:]')
			shift
			;;

    # Access service allocation.
    --access-service)
			ACCESS_SERVICE=${2}
			shift
			;;

		*)
			break

	esac
	shift
done

${DEBUG} && echo "Policies: ${AUTH_POLICIES}"
${DEBUG} && echo "Service: ${ACCESS_SERVICE}"

printf '%s\n' "$AUTH_POLICIES" | tr ';' '\n' |
while IFS=':' read -r route roles; do
	CONF_FILE="$ACCESS_FILE_DIR/access-identity-management-$route.conf"
  ${DEBUG} && echo "Creating file: ${CONF_FILE}"

	if [ "$ENVIRONMENT" = "PROD" ] || [ "$ENVIRONMENT" = "PRODUCTION" ]; then
		{
			printf 'auth_request /oauth2/auth_%s;\n\n' "$route"
			cat <<EOF
auth_request_set \$user \$upstream_http_x_auth_request_preferred_username;
auth_request_set \$email \$upstream_http_x_auth_request_email;
auth_request_set \$groups \$upstream_http_x_auth_request_groups;

error_page 401 = /oauth2/sign_in;

proxy_set_header X-User \$user;
proxy_set_header X-Email \$email;
proxy_set_header X-Groups \$groups;

location /oauth2/ {
    auth_request off;
    proxy_pass http://$ACCESS_SERVICE;
    proxy_hide_header Host;
    proxy_set_header Host \$server_name;

    proxy_set_header X-Original-URL \$scheme://\$host\$request_uri;
    proxy_set_header X-Auth-Request-Redirect \$scheme://\$host\$request_uri;
}

location = /oauth2/auth_$route {
    internal;
    auth_request off;

    proxy_pass http://$ACCESS_SERVICE/oauth2/auth?allowed_groups=role:$roles;

    proxy_hide_header Host;
    proxy_set_header Host \$server_name;

    proxy_set_header Content-Length "";
    proxy_pass_request_body off;
}
EOF
		} > "$CONF_FILE"

	else
		: > "$CONF_FILE"

	fi

	${DEBUG} && echo "File access content: ${CONF_FILE}" && cat "${CONF_FILE}"
done
