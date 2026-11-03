# Bug candidates

Observed on 2026-11-03 while configuring the code review for this repository (AGENTS.md and
`src/agents/review/review.toml`). These are **candidates**: noticed while reading, not verified,
not triaged. Credentials are named by location only. Remove an entry once it is confirmed and
tracked elsewhere, or found not to be a bug.

- `nginx/script/nginx_sync_config.sh`: a failed download ends with `exit 0`, which callers read as "changed, reload".
- `nginx_sync_config.sh` and other scripts end with a top-level `return` although they are executed, not sourced.
- The cert and stream `wget` calls are not checked, and their failure can reach `rm -rf ${CERTS}/*`.
- `nginx_entrypoint.sh` appends `|| true` to every setup step.
- `web/Dockerfile` copies `static/`, which does not exist in the repository: the `web` image cannot build from a clean checkout.
- Several Dockerfiles clean `/var/lib/apt-get/lists` (the real path is `/var/lib/apt/lists`).
- Old upstream bases: `haproxy:2.3.7`, `httpd:2.4.48-buster`, `debian:11.10-slim`.
