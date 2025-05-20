#!/bin/sh

# Default script behavior.
#set -o pipefail

# Default parameters.
debug=${DEBUG:=false}
debug_opt=
skip_reload=false
skip_reload_param=""
reload_only_if_errors_change=false
conf_folder=/etc/nginx/
no_error_files_name_pattern=*.conf
upstream_folder=/etc/nginx/upstream.d

# For each argument.
while :; do
	case ${1} in
		
		# Debug argument.
		--debug)
			debug=true
			debug_opt="--debug"
			;;
			
		# If actual reload should be done only if errors change.
		--only-if-errors-change)
			reload_only_if_errors_change=true
			;;
			
		# If actual reload should be done.
		--no-reload)
			skip_reload=true
			skip_reload_param="--no-reload"
			;;
			
		# No more options.
		*)
			break

	esac 
	shift
done

# Enables interruption signal handling.
trap - INT TERM

# Print arguments if on debug mode.
${debug} && echo "Running 'nginx_check_config'"

# Error files.
initial_no_error_files=$( find ${conf_folder} -type f -name "${no_error_files_name_pattern}" )
nginx_revert_config_errors ${debug_opt}

# Test files with errors.
${debug} && nginx -t || true
nginx_test=$( nginx -t 2>&1 1>/dev/null )
${debug} && echo "nginx_test=${nginx_test}"
error_pattern="\[emerg\]"
nginx_error=$( echo ${nginx_test} | grep "${error_pattern}" )
config_valid=true
last_nginx_file_with_error=
cert_with_error=
conf_file_format="/etc/nginx/[^ ]*/[^ ]*.conf"
while [ ! -z "${nginx_error}" ]
do
	config_valid=false
	
	# Get only emerg output
	nginx_error=$( echo ${nginx_error} | sed "s/.*${error_pattern}//")

	# Tries to get the file with error.
	nginx_file_with_error=$( echo ${nginx_error} | grep "${conf_file_format}" | sed -e "s#.*\(${conf_file_format}\).*#\1#" )
	
    # Gets the file with certificate error.
    if [ -z "${nginx_file_with_error}" ]
    then
        cert_with_error=$( echo ${nginx_error} | grep "cannot load certificate" | sed -e "s#.*cannot load certificate\( key\)\? \"##" -e "s#\.pem.*#\.pem#" )
		if [ ! -z "${cert_with_error}" ]
		then
	        nginx_file_with_error=$( grep -R -m 1 "${cert_with_error}" "${conf_folder}" 2>/dev/null | cut -d: -f1 )
			echo "Certificate ${cert_with_error} not found"
		fi
    fi
    
	# If it is the main file, breaks.
	if [ "${nginx_file_with_error}" = "" ] 
	then
	    echo "No file with error. Stops trying to fix."
        break
	elif [ "${nginx_file_with_error}" = "${last_nginx_file_with_error}" ]
	then
		echo "Error loop. Stops trying to fix."
		break
	fi
	
	# Moves the file with error.
	last_nginx_file_with_error=${nginx_file_with_error}
	echo "Error in file. Moving file ${nginx_file_with_error} to ${nginx_file_with_error}.err"
	mv -f ${nginx_file_with_error} ${nginx_file_with_error}.err
	
	# Gets the next error.
	nginx_test=$( nginx -t 2>&1 1>/dev/null )
	${debug} && echo "${nginx_test}"
	nginx_error=$( echo ${nginx_test} | grep "${error_pattern}" )
	${debug} && echo ${nginx_error}
	
done
final_no_error_files=$( find ${conf_folder} -type f -name "${no_error_files_name_pattern}" )

# Checks if there are new configuration files withou errors.
should_contain_list=${initial_no_error_files}
to_be_contained_list=${final_no_error_files}
new_files_without_errors=false
for to_be_contained_item in ${to_be_contained_list}
do
	if ! echo ${should_contain_list} | grep -q ${to_be_contained_item}
    then
    	echo "New file without errors: ${to_be_contained_item}"
        new_files_without_errors=true
        break
    fi
done
${debug} && echo "new_files_without_errors=${new_files_without_errors}"

# Reloads configuration.
should_reload=false
if ${skip_reload}
then
    echo "No reloading defined."
else
    if ${reload_only_if_errors_change}
    then
    	if ${new_files_without_errors}
    	then
    		echo "New configuration files without errors."
    		should_reload=true
    	else
    	    echo "No new configuration files without errors. Skipping reload."
    		should_reload=false
    	fi
    else
    	should_reload=true
    fi
fi

# If a dynamic upstream has changed reload config
last_modify=$(stat --format '%y' ${upstream_folder}/upstream-vhost.conf)
if [ -f ${upstream_folder}/.vhost_last_stat ]; then
	if [ "${last_modify}" != "$(cat ${upstream_folder}/.vhost_last_stat)" ]; then
		echo "nginx_check_config: [INFO] Update vhost_last_stat"
		echo "${last_modify}" > ${upstream_folder}/.vhost_last_stat
		should_reload=true
	fi
else
	echo "nginx_check_config: [INFO] Populate vhost_last_stat"
	echo "${last_modify}" > ${upstream_folder}/.vhost_last_stat
fi

if ${should_reload}
then
	echo "Reloading configuration."
	${skip_reload} || nginx_variables ${skip_reload_param}
	${skip_reload} || nginx -s reload
fi

# Returns if the configuration is valid.
if ${config_valid}
then
	return 0
else 
	return 1
fi
