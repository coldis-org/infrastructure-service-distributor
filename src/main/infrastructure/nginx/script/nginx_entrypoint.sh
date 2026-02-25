#!/bin/sh -e

# Starts syslog.
rsyslogd &
RSYSLOG_PID=$!

# Starts cron.
env > /etc/docker_env
chmod +x /etc/docker_env
NGINX_JOBS_FILE=/etc/cron.d/nginx_jobs
envsubst < "${NGINX_JOBS_FILE}" | sponge "${NGINX_JOBS_FILE}"
crontab /etc/cron.d/nginx_jobs
service cron start

# Tune Nginx opts.
. /usr/bin/nginx_tune_opts
nginx_tune_opts

# Create common config files
nginx_create_access_control_config --auth-policies "${AUTH_POLICIES}" --environment "${ENVIRONMENT}" --access-service ${ACCESS_SERVICE} || true

# Sync config.
nginx_sync_config || true
. nginx_install_all_basic_certs || true
nginx_variables || true
nginx_update_nets || true

# Checks config.
nginx_check_config --no-reload || true

# Runs original command.
exec "$@"

# Stops syslog.
kill -s SIGTERM $RSYSLOG_PID
