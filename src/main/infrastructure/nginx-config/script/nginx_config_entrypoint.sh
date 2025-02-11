#!/bin/sh -e

# Exposes configuration files.
nginx_expose_conf

# Runs original command.
nginx_entrypoint "$@"