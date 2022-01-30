#!/bin/sh -e

# Starts cron.
env > /etc/docker_env
chmod +x /etc/docker_env
service cron start

# Creates client certificates.
nginx_install_cert --self-signed "/C=BR/ST=SaoPaulo/L=SaoPaulo/O=SuperSim/OU=Com/OU=Br/CN=client"

# Replaces variables in config files.
nginx_variables

# Runs original command.
exec "$@"