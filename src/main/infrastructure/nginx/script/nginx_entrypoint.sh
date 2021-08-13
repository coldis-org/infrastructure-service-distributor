#!/bin/sh -e

# Starts cron.
env > /etc/docker_env
chmod +x /etc/docker_env
service cron start

nginx_variables

exec "$@"