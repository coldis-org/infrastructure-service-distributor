#!/bin/sh -e

if [ "${DNS_SERVER}" = "" ]
then
	export DNS_SERVER=${DNS_SERVER:-$(grep -i '^nameserver' /etc/resolv.conf |head -n1|cut -d ' ' -f2)}
fi

# Variables.
ENV_VARIABLES=$(awk 'BEGIN{for(v in ENVIRON) print "$"v}')

FILES="\
$(ls /etc/modsecurity.d/ | sed "s#^#/etc/modsecurity.d/#") \
$(ls /etc/nginx/ | sed "s#^#/etc/nginx/#") \
$(ls /etc/nginx/conf.d | sed "s#^#/etc/nginx/conf.d/#") \
$(ls /etc/nginx/conf.d/include.d | sed "s#^#/etc/nginx/conf.d/include.d/#") \
$(ls /etc/nginx/conf.d/general.d | sed "s#^#/etc/nginx/conf.d/general.d/#") \
$(ls /etc/nginx/conf.d/vhost.d | sed "s#^#/etc/nginx/conf.d/vhost.d/#") \
$(ls /etc/nginx/vhost.d | sed "s#^#/etc/nginx/vhost.d/#")
"
for FILE in $FILES; do
	if [ -f "$FILE" ]; then
		envsubst "$ENV_VARIABLES" <"$FILE" | sponge "$FILE"
	fi
done
