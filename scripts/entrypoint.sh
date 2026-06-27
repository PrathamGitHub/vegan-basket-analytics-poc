#!/usr/bin/env bash
# Docker entrypoint for the pipeline container.
#
# Exports all container environment variables into /etc/environment so that
# cron jobs (which start in a stripped environment) can access them.
# Then starts cron in the foreground.

set -euo pipefail

echo "[entrypoint] Exporting environment to /etc/environment..."

# Write current env vars (skip shell internals that would break /etc/environment)
printenv | grep -Ev '^(HOSTNAME|HOME|PWD|SHLVL|_|OLDPWD|PATH)=' \
    | sed 's/=\(.*\)/="\1"/' \
    >> /etc/environment

echo "[entrypoint] Cron schedule: 17:30 UTC (23:00 IST) daily"
echo "[entrypoint] Logs: /app/data/logs/ingest-YYYY-MM-DD.log"
echo "[entrypoint] Starting cron..."

exec cron -f
