# AGENTS.md

Edge and proxy images of the coldis platform (GitHub `coldis-org/infrastructure-service-distributor`):
nginx built from source with ModSecurity (OWASP CRS) and the VTS status module, an nginx variant
that exposes its configuration, an haproxy layer-4 balancer, pgbouncer built from source with PAM
LDAP, and an Apache httpd with ModSecurity. No application code; `pom.xml` (parent
`org.coldis:configuration`) carries no build of its own.

Image layering: `nginx` copies the `os_*` scripts out of `coldis/infrastructure-os` in a build
stage and builds on the official `nginx` image; `nginx-config` builds `FROM` a released `nginx`
image (`coldis/infrastructure-service-distributor-nginx:1.9.9`). `layer4`, `pg` and `web` build
on upstream images (`haproxy:2.3.7`, `debian:11.10-slim`, `httpd:2.4.48-buster`).

## Layout

All under `src/main/infrastructure/`.

| Path | Holds |
|------|-------|
| `nginx/` | nginx `NGINX_VERSION` (1.30.6) + ModSecurity, VTS, NDK, set-misc; `config/nginx`, `config/modsecurity` (CRS), `html/`, `script/nginx_*.sh`, `cron/nginx_jobs` |
| `nginx-config/` | Adds `nginx_expose_conf` and an extra `vhost.d/config.conf` on top of `nginx` |
| `layer4/` | haproxy: `config/*.cfg`, `script/haproxy_*.sh`, `cron/haproxy_jobs`, `rsyslog.conf` |
| `pg/` | pgbouncer `PGBOUNCER_VERSION` (1.24.1): `config/pgbouncer.ini`, `config/pam_ldap.conf`, `script/pgbouncer_*.sh` |
| `web/` | Apache httpd: `config/` (with `extra/crs`), `config/original/` (upstream reference copies), `script/apache_*.sh`, `cron/apache_jobs` |
| `*/service.json` | Marathon-style app definitions |

## Commands

No build script or CI. Each image builds from its folder:

```bash
docker build -t coldis/infrastructure-service-distributor-nginx:<tag> src/main/infrastructure/nginx
docker build src/main/infrastructure/<nginx-config|layer4|pg>
```

`web` does not build from a clean checkout: its Dockerfile copies `static/`, which is not in the
repository.

The threat-blocklist test runs inside a built `nginx` image, against the script and conf.d files it
installs (needs network once, for openssl):

```bash
docker run --rm --entrypoint bash -v "$PWD/src/test/infrastructure/nginx:/test:ro" \
  coldis/infrastructure-service-distributor-nginx:<tag> /test/threat_blocklist_test.sh
```

Run it on any change to `nginx_update_threat_blocklist` or the `threat-blocklist*` files, and record
the result in the local check (`tests=<passed>/<run>`).

## Gotchas

- **Config is rendered at boot with `envsubst` over every environment variable.**
  `nginx_variables` does it to every file under `/etc/nginx`, `/etc/nginx/conf.d/*`,
  `/etc/modsecurity.d` and `/etc/rsyslog.conf`; `pgbouncer_init` to `pgbouncer.ini` and
  `pam_ldap.conf`. An nginx `$variable` whose name matches an environment variable is replaced.
- **Cron tables are templates too.** `nginx_jobs` uses `${CERT_UPDATE_SCHEDULE}`,
  `${CONFIG_UPDATE_SCHEDULE}`, `${CERT_CLEANUP_SCHEDULE}`, rendered by `nginx_entrypoint`. Jobs
  load the boot environment from `/etc/docker_env` and log to `/proc/1/fd/1`.
- **`nginx-config` replaces `nginx_jobs` wholesale** (same file name), so a job added to the
  `nginx` table must be added to the `nginx-config` one as well.
- **A broken config file is moved aside, not fatal.** `nginx_check_config` moves the file with the
  error to `.err` and retests it with backoff (`nginx_revert_config_errors`, state in
  `/etc/nginx/vhost.d/.config_retest_state`), so nginx keeps serving the rest. The entrypoint's
  setup steps all run with `|| true`.
- **`*.conf.default` files are templates, not live config.** `nginx_update_nets` and
  `nginx_update_security_rules` copy them (`networks.conf.default`, `reqlimit*.conf.default`,
  `access-anynet.conf.default`, the CRS exclusions) into the `.conf` that `nginx.conf` includes,
  so edit the `.default` and let the script regenerate.
- **pgbouncer runs several processes**: `pgbouncer.ini` is copied per process with
  `CURRENT_PROCESS` replaced in each copy.

## Conventions

- Scripts live in each image's `script/`, named `<image>_*.sh` (`nginx_`, `haproxy_`,
  `pgbouncer_`, `apache_`), copied to `/opt/<image>-script` and linked into `/usr/bin` without the
  `.sh` suffix. They are `#!/bin/sh` (some `#!/bin/sh -e`) and take `--debug`.
- Tunables are environment variables with a default in the Dockerfile `ENV` block, rendered into
  the config files at boot; schedules are environment variables too.
- Cron tables live in `cron/`, are copied to `/etc/cron.d` and installed with `crontab`.

## Workspace

This repository expects `supersim-infrastructure-code-reviewer` checked out next to it
(`../supersim-infrastructure-code-reviewer`; clone it there from the internal Git host if it's
missing). The review-gate summary and the local review both live in it.

## Review

The gates are those of `src/agents/review/review.toml`, read from master, so a branch can't weaken
its own review: `security`, `platform-image`, `platform-runtime`, `platform-config` and the
`shellcheck` rule (severity `warning`, HIGH on failure). What each gate stops:
`../supersim-infrastructure-code-reviewer/local-review/GATES.md`. The ModSecurity CRS `*.data`
files and the `html/` pages are reviewed by no gate beyond `security`. The PR description must name
every image, upstream version, default, port, schedule, rate limit, access rule and certificate or
data path changed.

Before pushing, run the local review: follow
`../supersim-infrastructure-code-reviewer/local-review/REVIEW.md`. It ends with
`local-check attest`. Push only when the developer asks.
