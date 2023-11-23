#!/bin/sh -e

# Default parameters.
DEBUG=${DEBUG:=false}
DEBUG_OPT=
SKIP_RELOAD=false
SKIP_RELOAD_PARAM=""

# For each argument.
while :; do
	case ${1} in
		
		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
			;;
			
		# Files.
		--files)
			FILES=${2}
			shift
			;;
			
		# If actual reload should be done.
		--no-reload)
			SKIP_RELOAD=true
			SKIP_RELOAD_PARAM="--no-reload"
			;;
			
		# No more options.
		*)
			break

	esac 
	shift
done

if [ -z "${DNS_SERVER}" ]
then
	export DNS_SERVER=${DNS_SERVER:-$(grep -i '^nameserver' /etc/resolv.conf |head -n1|cut -d ' ' -f2)}
fi

# Variables.
ENV_VARIABLES=$(awk 'BEGIN{for(v in ENVIRON) print "$"v}')

if [ -z "${FILES}" ]
then
FILES="\
$(ls /etc/modsecurity.d/ | sed "s#^#/etc/modsecurity.d/#") \
$(ls /etc/modsecurity.d/custom-rules | sed "s#^#/etc/modsecurity.d/custom-rules/#") \
$(ls /etc/nginx/ | sed "s#^#/etc/nginx/#") \
$(ls /etc/nginx/conf.d | sed "s#^#/etc/nginx/conf.d/#") \
$(ls /etc/nginx/conf.d/include.d | sed "s#^#/etc/nginx/conf.d/include.d/#") \
$(ls /etc/nginx/conf.d/general.d | sed "s#^#/etc/nginx/conf.d/general.d/#") \
$(ls /etc/nginx/conf.d/vhost.d | sed "s#^#/etc/nginx/conf.d/vhost.d/#") \
$(ls /etc/nginx/vhost.d | sed "s#^#/etc/nginx/vhost.d/#")
"
fi

# Replaces variables in files.
for FILE in $FILES; do
	if [ -f "$FILE" ]; then
		envsubst "$ENV_VARIABLES" <"$FILE" | sponge "$FILE"
	fi
done
