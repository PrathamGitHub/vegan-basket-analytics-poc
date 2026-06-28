#!/usr/bin/env bash
# Daily ingestion wrapper for Vegan Basket Analytics.
#
# Usage:
#   ./scripts/run_daily.sh            # normal run (revision guard active)
#   FORCE_RUN=true ./scripts/run_daily.sh   # bypass guard, always load
#
# Logs are written to data/logs/ingest-YYYY-MM-DD.log (one file per day).
# Designed to be called by the systemd timer or cron.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export INGEST_START_EPOCH="$(date +%s)"

# ── Logging ──────────────────────────────────────────────────────────────────
LOG_DIR="$ROOT/data/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/ingest-$(date +%Y-%m-%d).log"

# Redirect all output (stdout + stderr) to the log file AND the terminal.
exec > >(tee -a "$LOG_FILE") 2>&1

ts() { date '+%Y-%m-%d %H:%M:%S %Z'; }
log() { echo "[$(ts)] $*"; }

# ── Rill stop/start helpers (DuckDB single-writer coordination) ───────────────
DOCKER_SOCK="/var/run/docker.sock"
RILL_CONTAINER="${RILL_CONTAINER_NAME:-vegan-basket-rill}"
_rill_stopped=false

_docker_api() {
    curl -sf --unix-socket "$DOCKER_SOCK" "$@"
}

_stop_rill() {
    [[ ! -S "$DOCKER_SOCK" ]] && {
        log "WARNING: Docker socket not found — Rill will not be stopped. DuckDB lock conflict likely."
        return
    }
    local status
    status=$(_docker_api "http://localhost/containers/${RILL_CONTAINER}/json" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['State']['Status'])" 2>/dev/null \
        || echo "not_found")
    if [[ "$status" == "running" ]]; then
        log "Stopping Rill ($RILL_CONTAINER) — acquiring exclusive DuckDB access..."
        _docker_api -X POST "http://localhost/containers/${RILL_CONTAINER}/stop" >/dev/null
        _rill_stopped=true
        log "Rill stopped."
    else
        log "Rill is not running (status: ${status}) — nothing to stop."
    fi
}

_start_rill() {
    [[ "$_rill_stopped" != true ]] && return
    [[ ! -S "$DOCKER_SOCK" ]] && return
    log "Starting Rill ($RILL_CONTAINER)..."
    _docker_api -X POST "http://localhost/containers/${RILL_CONTAINER}/start" >/dev/null \
        || log "Warning: could not start Rill (non-fatal)"
    _rill_stopped=false
    log "Rill started."
}

_on_error() {
    local exit_code=$?
    log "ERROR: daily ingest failed (exit ${exit_code})"
    _start_rill
    python -m src.telegram_digest --failure --exit-code="${exit_code}" \
        || log "Telegram failure alert could not be sent (non-fatal)"
    exit "${exit_code}"
}
trap _on_error ERR

log "==============================="
log "Vegan Basket daily ingest START"
log "==============================="
log "Working dir : $ROOT"
log "Log file    : $LOG_FILE"
[[ "${FORCE_RUN:-false}" != "false" ]] && log "FORCE_RUN   : enabled"

# ── Virtualenv ───────────────────────────────────────────────────────────────
if [[ -f "$ROOT/.venv/bin/activate" ]]; then
    # shellcheck disable=SC1091
    source "$ROOT/.venv/bin/activate"
    log "Virtualenv  : $ROOT/.venv (activated)"
elif [[ -n "${VIRTUAL_ENV:-}" ]]; then
    log "Virtualenv  : $VIRTUAL_ENV (already active)"
else
    log "Virtualenv  : none detected — using system Python"
fi

# ── .env (belt-and-suspenders; systemd EnvironmentFile handles it too) ───────
if [[ -f "$ROOT/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT/.env"
    set +a
    log ".env        : loaded"
fi

# ── Pipeline (dlt → DuckDB) ──────────────────────────────────────────────────
_stop_rill
log "--- Running ingestion pipeline ---"
python -m src.pipeline
log "--- Pipeline finished ---"

# ── dbt transforms ───────────────────────────────────────────────────────────
log "--- Running dbt ---"
dbt run --project-dir "$ROOT/dbt" --profiles-dir "$ROOT/dbt"
log "--- dbt finished ---"

# ── Release DuckDB lock before Telegram digest ────────────────────────────────
_start_rill

log "--- Sending Telegram digest ---"
python -m src.telegram_digest \
    || log "Telegram digest could not be sent (non-fatal)"

log "=============================="
log "Vegan Basket daily ingest DONE"
log "=============================="
