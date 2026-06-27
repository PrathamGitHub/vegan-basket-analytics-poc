# Systemd Timer — Install Guide

Runs `scripts/run_daily.sh` (pipeline + dbt) every night at **23:00 IST** using
a user-mode systemd timer. No root access required.

---

## Prerequisites

- The repo is cloned at `~/work/projects/vegan-basket-analytics-poc`  
  (if it lives elsewhere, update `WorkingDirectory` / `ExecStart` in the `.service` file)
- `.env` file is present at the repo root with all required variables
- Python virtualenv is at `.venv/` inside the repo (or Python/dbt are on `$PATH`)
- `dbt` is installed and `dbt/profiles.yml` is configured

---

## Install (one-time)

```bash
# 1. Copy the unit files into your user systemd directory
UNIT_DIR="$HOME/.config/systemd/user"
mkdir -p "$UNIT_DIR"

REPO="$HOME/work/projects/vegan-basket-analytics-poc"
cp "$REPO/deploy/systemd/vegan-basket-ingest.service" "$UNIT_DIR/"
cp "$REPO/deploy/systemd/vegan-basket-ingest.timer"   "$UNIT_DIR/"

# 2. Reload systemd to pick up the new files
systemctl --user daemon-reload

# 3. Enable and start the timer (survives reboots)
systemctl --user enable --now vegan-basket-ingest.timer

# 4. Verify the timer is scheduled
systemctl --user list-timers vegan-basket-ingest.timer
```

---

## Verify & Operate

```bash
# Check timer status and next fire time
systemctl --user status vegan-basket-ingest.timer

# View logs from the last run
journalctl --user -u vegan-basket-ingest -n 50

# Follow logs live (useful during a manual test run)
journalctl --user -u vegan-basket-ingest -f

# Trigger a run immediately (bypasses the timer, good for testing)
systemctl --user start vegan-basket-ingest.service

# Force a run even if nothing changed in the sheet
FORCE_RUN=true systemctl --user start vegan-basket-ingest.service

# Disable the timer temporarily
systemctl --user stop vegan-basket-ingest.timer

# Remove it entirely
systemctl --user disable --now vegan-basket-ingest.timer
```

---

## Logs

The script also writes timestamped logs to:

```
data/logs/ingest-YYYY-MM-DD.log
```

These are kept separately from the journal for easy sharing or inspection.

---

## Alternative: crontab

If you prefer cron over systemd, add this line via `crontab -e`:

```cron
# Run at 23:00 IST (17:30 UTC) every day
30 17 * * * cd /home/$USER/work/projects/vegan-basket-analytics-poc && \
    bash scripts/run_daily.sh >> data/logs/ingest-$(date +\%Y-\%m-\%d).log 2>&1
```

> **Note:** crontab does not source `.env` automatically. Export variables in a
> wrapper or use `env $(cat .env | xargs)` before the script call.

---

## How the revision guard works

Before running the full pipeline, `scripts/run_daily.sh` → `src/pipeline.py`
calls the Google Sheets API to fetch **column A only** from each tab (a
three-call lightweight pre-check) and compares the row counts against
`data/ingest_state.json` (written after every successful run).

| Scenario | Outcome |
|---|---|
| Row counts unchanged | Pipeline exits cleanly; dbt still runs (idempotent) |
| Row counts changed | Full dlt load + DuckDB write + dbt run |
| `data/ingest_state.json` missing (first run) | Always runs |
| `FORCE_RUN=true` env var | Always runs, guard bypassed |
