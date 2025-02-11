#!/bin/sh -e

# Creates client certificates.
nginx_session_ticket --only-if-missing
nginx_install_cert --self-signed "/C=BR/ST=SaoPaulo/L=SaoPaulo/O=SuperSim/OU=Com/OU=Br/CN=client"

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
nginx_variables || true
nginx_update_nets || true
nginx_check_config --no-reload || true

# Runs original command.
exec "$@"