#!/bin/sh -e

# Starts syslog.
rsyslogd &
RSYSLOG_PID=$!

# Starts cron.
env > /etc/docker_env
chmod +x /etc/docker_env
envsubst < /etc/cron.d/nginx_jobs > /etc/cron.d/nginx_jobs
crontab /etc/cron.d/nginx_jobs
service cron start

# Tune Nginx opts.
. /usr/bin/nginx_tune_opts
nginx_tune_opts

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
