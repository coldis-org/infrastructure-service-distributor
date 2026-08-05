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
${debug} && echo "nginx_check_config: [DEBUG] Running"

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
moved_count=0
vhost_audit_done=false
conf_file_format="/etc/nginx/[^ ]*/[^ ]*.conf"
while [ ! -z "${nginx_error}" ]
do
	config_valid=false
	error_reason=
	cert_with_error=

	# Get only emerg output
	nginx_error=$( echo ${nginx_error} | sed "s/.*${error_pattern}//")

	# Tries to get the file with error.
	nginx_file_with_error=$( echo ${nginx_error} | grep "${conf_file_format}" | sed -e "s#.*\(${conf_file_format}\).*#\1#" )
	if [ ! -z "${nginx_file_with_error}" ]
	then
		error_reason="${nginx_error}"
	fi

    # Gets the file with certificate error. Nginx does not name the offending file, so it is
    # looked up by the certificate path, over the whole tree so that stream.d/upstream.d are
    # covered too: -F because the path is full of dots, -l for plain file names (-m 1 counts
    # per file, so it yields one line per matching file), --include so only an active *.conf
    # can be blamed — never a stale copy (.old/.tmp left behind by nginx_add_vhost while it
    # calls this script) nor an already quarantined one (.err/.dead) — and nginx.conf itself
    # is excluded, since moving it away would take the whole server down.
    if [ -z "${nginx_file_with_error}" ]
    then
        cert_with_error=$( echo ${nginx_error} | grep "cannot load certificate" | sed -e "s#.*cannot load certificate\( key\)\? \"##" -e "s#\.pem.*#\.pem#" )
		if [ ! -z "${cert_with_error}" ]
		then
	        nginx_file_with_error=$( grep -R -l -I -F --include='*.conf' "${cert_with_error}" "${conf_folder}" 2>/dev/null \
	        		| grep -v -x -F "${conf_folder}nginx.conf" | head -1 )
			error_reason="certificate ${cert_with_error} could not be loaded (file missing or unreadable)"
		fi
    fi

    # Gets the file with unknown variable error.
    if [ -z "${nginx_file_with_error}" ]
    then
        unknown_var=$( echo ${nginx_error} | grep 'unknown "' | sed -e 's#.*unknown "##' -e 's#".*##' )
        if [ ! -z "${unknown_var}" ]
        then
            nginx_file_with_error=$( grep -R -i -l -m 1 "\${${unknown_var}}" ${conf_folder}vhost.d/ ${conf_folder}conf.d/vhost.d/ 2>/dev/null | head -1 )
            if [ ! -z "${nginx_file_with_error}" ]
            then
                error_reason="unknown variable '${unknown_var}' referenced by this file"
            fi
        fi
    fi

	# A certificate error whose path is in no active config (so the lookup above found
	# nothing): bisects the vhosts to find and quarantine the one that fails to load it.
	# Restricted to this case on purpose — for an error that names no file and is not about
	# a certificate (typically a global limit such as "could not build ... hash", which no
	# single vhost owns) bisecting would quarantine whichever vhost happens to trip the
	# limit first. Done at most once per run: a second pass would find nothing new, so the
	# loop is still guaranteed to terminate on the check below.
	if [ "${nginx_file_with_error}" = "" ] && [ ! -z "${cert_with_error}" ] && ! ${vhost_audit_done}
	then
		echo "nginx_check_config: [WARN] Error names no configuration file; bisecting the vhosts."
		vhost_audit_done=true
		nginx_test_vhosts ${debug_opt}
		nginx_test=$( nginx -t 2>&1 1>/dev/null )
		${debug} && echo "${nginx_test}"
		nginx_error=$( echo ${nginx_test} | grep "${error_pattern}" )
		${debug} && echo ${nginx_error}
		continue
	fi

	# If it is the main file, breaks.
	if [ "${nginx_file_with_error}" = "" ]
	then
	    echo "nginx_check_config: [WARN] No file with error. Stops trying to fix."
        break
	elif [ "${nginx_file_with_error}" = "${last_nginx_file_with_error}" ]
	then
		echo "nginx_check_config: [WARN] Error loop on ${nginx_file_with_error}. Stops trying to fix."
		break
	fi

	# Never move shared include fragments: the error is reported at the fragment's
	# line, but the real problem is in a file that includes it in a wrong context
	# (which nginx does not name). Identify and quarantine the offending includer(s)
	# by testing each file that includes the fragment, then re-test and continue.
	case "${nginx_file_with_error}" in
		*/include.d/*)
			echo "nginx_check_config: [WARN] Error references include fragment ${nginx_file_with_error}; testing the files that include it."
			nginx_test_vhosts --fragment "${nginx_file_with_error}" ${debug_opt}
			last_nginx_file_with_error=${nginx_file_with_error}
			nginx_test=$( nginx -t 2>&1 1>/dev/null )
			${debug} && echo "${nginx_test}"
			nginx_error=$( echo ${nginx_test} | grep "${error_pattern}" )
			${debug} && echo ${nginx_error}
			continue
			;;
	esac

	# Moves the file with error, logging the reason on a single line (the trailing
	# "nginx: configuration file ... test failed" boilerplate is stripped).
	last_nginx_file_with_error=${nginx_file_with_error}
	[ -z "${error_reason}" ] && error_reason="${nginx_error}"
	error_reason=$( echo "${error_reason}" | sed -e 's/ nginx: configuration file .* test failed//' -e 's/^[[:space:]]*//' )
	if mv -f ${nginx_file_with_error} ${nginx_file_with_error}.err 2>/dev/null
	then
		moved_count=$((moved_count + 1))
		echo "nginx_check_config: [WARN] Moved ${nginx_file_with_error} to .err — ${error_reason}"
	else
		echo "nginx_check_config: [ERROR] Failed to move ${nginx_file_with_error} (check permissions, e.g. immutable flag via 'lsattr'). Stops trying to fix."
		break
	fi

	# Gets the next error.
	nginx_test=$( nginx -t 2>&1 1>/dev/null )
	${debug} && echo "${nginx_test}"
	nginx_error=$( echo ${nginx_test} | grep "${error_pattern}" )
	${debug} && echo ${nginx_error}
	
done
echo "nginx_check_config: [INFO] Moved ${moved_count} file(s) with errors this run."
final_no_error_files=$( find ${conf_folder} -type f -name "${no_error_files_name_pattern}" )

# Checks if there are new configuration files withou errors.
should_contain_list=${initial_no_error_files}
to_be_contained_list=${final_no_error_files}
new_files_without_errors=false
for to_be_contained_item in ${to_be_contained_list}
do
	if ! echo ${should_contain_list} | grep -q ${to_be_contained_item}
    then
    	echo "nginx_check_config: [INFO] New file without errors: ${to_be_contained_item}"
        new_files_without_errors=true
        break
    fi
done
${debug} && echo "new_files_without_errors=${new_files_without_errors}"

# Reloads configuration.
should_reload=false
if ${skip_reload}
then
    echo "nginx_check_config: [INFO] No reloading defined."
else
    if ${reload_only_if_errors_change}
    then
    	if ${new_files_without_errors}
    	then
    		echo "nginx_check_config: [INFO] New configuration files without errors."
    		should_reload=true
    	else
    	    echo "nginx_check_config: [INFO] No new configuration files without errors. Skipping reload."
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
	echo "nginx_check_config: [INFO] Reloading configuration."
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
