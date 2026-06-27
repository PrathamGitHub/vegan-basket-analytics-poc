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

_on_error() {
    local exit_code=$?
    log "ERROR: daily ingest failed (exit ${exit_code})"
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
log "--- Running ingestion pipeline ---"
python -m src.pipeline
log "--- Pipeline finished ---"

# ── dbt transforms ───────────────────────────────────────────────────────────
log "--- Running dbt ---"
dbt run --project-dir "$ROOT/dbt" --profiles-dir "$ROOT/dbt"
log "--- dbt finished ---"

log "--- Sending Telegram digest ---"
python -m src.telegram_digest \
    || log "Telegram digest could not be sent (non-fatal)"

log "=============================="
log "Vegan Basket daily ingest DONE"
log "=============================="
