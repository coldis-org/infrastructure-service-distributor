#!/bin/sh

# Memory limit.
memory_limit() {
	default_mem=$(( 1024 * 1024 * 1024 )) # 1GB
	max_mem=9223372036854771712
	mem=$( cat "/sys/fs/cgroup/memory/memory.limit_in_bytes" 2>/dev/null )
	if [ -z "${mem}" ] || [ "${mem}" = "${max_mem}" ]
	then
		mem="${default_mem}"
	fi
	echo "${mem}"
}
echo "memory_limit=$(memory_limit)"

# Gets Nginx tund opts.
nginx_tune_opts() {
	
#	VIRTUAL_THREADS_PARALELLISM_PROC_PERC=3000
#	VIRTUAL_THREADS_MAX_POOL_MEMORY_PERC=200
#	VIRTUAL_THREADS_MAX_POOL_MAX=8192
#	MAX_RAM_PERC=80
#	MIN_RAM_PROD_PERC=70
#	MIN_RAM_NPROD_PERC=40
#	MAX_RAM_NEW_PERC=70
#	MAX_METASPACE_SIZE_PERC=10
#	ENVIRONMENT="production"
	
	# CPU.
	CPU_UNIT=100000
	if [ -z "${MAX_CPU}" ]
	then
		MAX_CPU=$(cat "/sys/fs/cgroup/cpu/cpu.cfs_quota_us" 2>/dev/null || echo "error")
	fi
	if [ -z "${MAX_CPU}" ] || [ "${MAX_CPU}" = "error" ] || [ ${MAX_CPU} -le 0 ]
	then
		MAX_CPU=$((1 * CPU_UNIT))
	fi
	
	# Max memory.
	if [ -z "${MAX_MEMORY}" ]
	then
		MAX_MEMORY=$(memory_limit || echo "error")
	fi
	if [ -z "${MAX_MEMORY}" ] || [ "${MAX_MEMORY}" = "error" ] || [ ${MAX_MEMORY} -le 0 ]
	then
		MAX_MEMORY=$(( 1024 * 1024 * 1024 )) # Default to 1G.
	fi
	MAX_MEMORY=$((MAX_MEMORY / 1024 / 1024)) # MB

	
	if [ -z "${PROCESSES}" ]
	then
		PROCESSES=$(( PROCESSES_PROC_PERC * MAX_CPU / CPU_UNIT / 100 ))
	fi
	
	if [ -z "${THREADS}" ]
	then
		THREADS=$(( THREADS_PROC_PERC * MAX_CPU / CPU_UNIT / 100 ))
	fi
	THREADS=$((THREADS > MAX_THREADS ? MAX_THREADS : THREADS))
	
	if [ -z "${CONNECTIONS}" ]
	then
		CONNECTIONS=$(( CONNECTIONS_MEM_PERC * MAX_MEMORY / 100 ))
	fi
	
	if [ -z "${THREAD_QUEUE}" ]
	then
		THREAD_QUEUE=$(( THREAD_QUEUE_MEM_PERC * MAX_MEMORY / 100 ))
	fi
	
	echo "MAX_MEMORY=${MAX_MEMORY}"
	echo "MAX_CPU=${MAX_CPU}"
	echo "PROCESSES=${PROCESSES}"
	echo "CONNECTIONS=${CONNECTIONS}"
	echo "THREADS=${THREADS}"
	echo "THREAD_QUEUE=${THREAD_QUEUE}"
	export PROCESSES CONNECTIONS THREADS THREAD_QUEUE
}

#nginx_tune_opts
