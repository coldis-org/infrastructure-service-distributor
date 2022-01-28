#!/bin/sh -e

export DNS_SERVER=${DNS_SERVER:-$(grep -i '^nameserver' /etc/resolv.conf |head -n1|cut -d ' ' -f2)}

# Variables.
ENV_VARIABLES=$(awk 'BEGIN{for(v in ENVIRON) print "$"v}')

FILES="\
$(ls /etc/modsecurity.d/ | sed "s#^#/etc/modsecurity.d/#") \
$(ls /etc/nginx/ | sed "s#^#/etc/nginx/#") \
$(ls /etc/nginx/default.d | sed "s#^#/etc/nginx/default.d/#") \
$(ls /etc/nginx/conf.d | sed "s#^#/etc/nginx/conf.d/#") \
$(ls /etc/nginx/vhost.d | sed "s#^#/etc/nginx/vhost.d/#")
"
for FILE in $FILES; do
	if [ -f "$FILE" ]; then
		envsubst "$ENV_VARIABLES" <"$FILE" | sponge "$FILE"
	fi
done
