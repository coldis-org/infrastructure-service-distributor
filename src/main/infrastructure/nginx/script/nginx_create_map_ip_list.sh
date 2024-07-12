#!/bin/sh

INTRANET_FILE=/etc/nginx/conf.d/include.d/access-intranet.conf
IP_LIST_FILE=/etc/nginx/conf.d/include.d/map-ip-list
DEBUG=${DEBUG:=false}

while :; do
	case ${1} in
		
		# Debug argument.
		--debug)
			DEBUG=true
			DEBUG_OPT="--debug"
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

# Preparing our internal ips from allow file
ALLOW_IPS=$(cat $INTRANET_FILE)
ALLOW_IPS=$(echo "$ALLOW_IPS" | sed -e 's@#.*@@g' | sed -e '/^$/d' | tr -d '[:alpha:]'  | head -n -1 | sed -e 's@;@ 0;@g' | sed 's@^[0-9]*@\t@g')

${DEBUG} && echo "Running 'nginx_create_allow_list_ip_variable'"
${DEBUG} && echo "ALLOW_IPS = $ALLOW_IPS"

# Creating temp file
tee "$IP_LIST_FILE.tmp" > /dev/null << EOF
geo \$ip_list {
    default 1;
$ALLOW_IPS
}
 
map \$ip_list \$ip_list_key {
    0 "";
    1 \$binary_remote_addr;
}
EOF

# Update file if needed
if !(diff -s $IP_LIST_FILE.conf $IP_LIST_FILE.tmp); then
    mv $IP_LIST_FILE.conf $IP_LIST_FILE.old
    mv $IP_LIST_FILE.tmp $IP_LIST_FILE.conf
    rm $IP_LIST_FILE.old
else
    rm $IP_LIST_FILE.tmp
fi
