# Docker Deployment Guide — Vegan Basket Analytics

This guide walks you through building, configuring, and running the full
analytics stack on **any Linux server** (including WSL2) using Docker Compose.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Docker Compose                      │
│                                                      │
│  ┌──────────────────────┐  ┌──────────────────────┐ │
│  │   pipeline container  │  │   rill container     │ │
│  │                       │  │                      │ │
│  │  cron → 23:00 IST     │  │  rill start          │ │
│  │  python -m src.pipeline│  │  port 9009           │ │
│  │  dbt run              │  │                      │ │
│  │  telegram_digest      │  └──────────┬───────────┘ │
│  └──────────┬────────────┘             │             │
│             │  writes                  │ reads (RO)  │
│             ▼                          ▼             │
│       ./data/vegan_basket.duckdb  ◄────┘             │
│       ./data/logs/                                   │
│       ./credentials/ (read-only)                     │
└─────────────────────────────────────────────────────┘
            │                       │
            ▼                       ▼
    Google Sheets API        http://localhost:9009
    Telegram Bot API
```

**Two containers, one shared bind-mount:**

| Container | Image | Role |
|-----------|-------|------|
| `vegan-basket-pipeline` | `Dockerfile` | Nightly batch: dlt ingest → dbt → Telegram alert |
| `vegan-basket-rill` | `Dockerfile.rill` | Always-on Rill BI dashboard on port 9009 |

DuckDB is a file-based warehouse — no separate database container is needed.

---

## Prerequisites

| Requirement | Minimum version | Check |
|-------------|-----------------|-------|
| Docker Engine | 24.x | `docker --version` |
| Docker Compose plugin | v2.x | `docker compose version` |
| Internet access at build time | — | needed for pip, dbt deps, rill binary |

### Install Docker on Ubuntu / Debian / WSL2

```bash
# Remove old versions (if any)
sudo apt-get remove docker docker-engine docker.io containerd runc

# Add Docker's official GPG key
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add the repository
echo \
  "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Allow running Docker without sudo (log out/in after this)
sudo usermod -aG docker "$USER"
```

Verify:
```bash
docker --version          # Docker version 24.x.x
docker compose version    # Docker Compose version v2.x.x
```

---

## Step 1 — Clone the repository

```bash
git clone <your-repo-url> vegan-basket-analytics-poc
cd vegan-basket-analytics-poc
```

---

## Step 2 — Configure environment variables

```bash
cp .env.example .env
```

Open `.env` and fill in the required values:

```ini
# ── Required ──────────────────────────────────────────────────────────────────

# Google Sheets
GOOGLE_SHEET_ID=<paste your Sheet ID here>
# Path inside the container — do NOT change this value
GOOGLE_SERVICE_ACCOUNT_FILE=/app/credentials/service-account.json

# DuckDB — path inside the container — do NOT change this value
DUCKDB_PATH=/app/data/vegan_basket.duckdb

# dlt pipeline identifiers (defaults are fine)
DLT_PIPELINE_NAME=vegan_basket
DLT_DATASET_NAME=raw

# ── Optional: Telegram alerts ─────────────────────────────────────────────────
TELEGRAM_BOT_TOKEN=<your bot token from @BotFather>
TELEGRAM_CHAT_ID=<your chat / group ID>
# TELEGRAM_DIGEST_ENABLED=true
```

> **Important:** `DUCKDB_PATH` and `GOOGLE_SERVICE_ACCOUNT_FILE` must use the
> container-internal paths shown above. Docker Compose overrides them in
> `docker-compose.yml`, but it's good practice to set them correctly in `.env`
> too so they are consistent.

---

## Step 3 — Add the Google service account credentials

Place your service account JSON key at:

```
credentials/service-account.json
```

This directory is bind-mounted into the pipeline container as **read-only**.

```bash
# The directory already exists; just copy your key file in
cp /path/to/your-sa-key.json credentials/service-account.json
```

> Make sure the service account has **Viewer** access to the Google Sheet.

---

## Step 4 — Create the data directory

```bash
mkdir -p data/logs
```

The `data/` folder is the shared volume between the pipeline (read/write) and
Rill (read-only). DuckDB files, logs, and pipeline state files all live here.

---

## Step 5 — Build the Docker images

```bash
docker compose build
```

This performs two builds:

1. **`pipeline`** — Python 3.12 slim image; installs pip packages and dbt deps
   (downloads from the internet; ~2–3 min on first build).
2. **`rill`** — Debian slim image; downloads the official Rill CLI binary
   (~30–60 sec on first build).

Subsequent builds use the layer cache and are much faster.

---

## Step 6 — Start all services

```bash
docker compose up -d
```

This starts both containers in the background:

- `vegan-basket-pipeline` → cron daemon; waits for 17:30 UTC (23:00 IST) to
  fire the first run automatically.
- `vegan-basket-rill` → Rill server; immediately available at
  **http://localhost:9009**

---

## Step 7 — Trigger the pipeline manually (first-run test)

Don't wait until 23:00 for the first test:

```bash
docker compose run --rm pipeline /app/scripts/run_daily.sh
```

This runs the pipeline once in a temporary container, streams all output to
your terminal, and exits when done. Check the result:

```bash
# Verify DuckDB was populated
ls -lh data/vegan_basket.duckdb

# Open the Rill dashboard
xdg-open http://localhost:9009   # or just open the URL in your browser
```

---

## Day-to-day Operations

### View live pipeline logs

```bash
# Follow cron / entrypoint output
docker compose logs -f pipeline

# Read the structured daily log file
tail -f data/logs/ingest-$(date +%Y-%m-%d).log
```

### View Rill dashboard logs

```bash
docker compose logs -f rill
```

### Check service status

```bash
docker compose ps
```

### Force a pipeline run immediately

```bash
docker compose run --rm pipeline /app/scripts/run_daily.sh
```

Add `FORCE_RUN=true` to bypass the revision guard (always re-ingests from
Google Sheets even if row counts haven't changed):

```bash
docker compose run --rm -e FORCE_RUN=true pipeline /app/scripts/run_daily.sh
```

### Stop all services

```bash
docker compose down
```

DuckDB files and logs in `data/` are **not** removed — they are bind-mounted,
not managed volumes.

### Restart a single service

```bash
docker compose restart pipeline
docker compose restart rill
```

### Update after a code change

```bash
docker compose build pipeline   # or: build rill
docker compose up -d --no-deps pipeline
```

---

## Changing the Cron Schedule

The schedule is baked into the `Dockerfile` as a `/etc/cron.d/vegan-basket`
entry. The default is **17:30 UTC (23:00 IST)**.

To change it, edit the `RUN printf ...` line in `Dockerfile`:

```dockerfile
# Format: minute hour day month weekday
RUN printf '30 17 * * * root . /etc/environment; cd /app && /app/scripts/run_daily.sh\n' \
    > /etc/cron.d/vegan-basket && chmod 0644 /etc/cron.d/vegan-basket
```

Then rebuild:

```bash
docker compose build pipeline
docker compose up -d --no-deps pipeline
```

---

## Accessing the Rill Dashboard from a Remote Machine

By default, port 9009 is only exposed on `localhost` of the server. To reach it
from another machine on the same network, either:

**Option A — Change the port binding in `docker-compose.yml`:**
```yaml
ports:
  - "0.0.0.0:9009:9009"   # listen on all interfaces
```

**Option B — SSH tunnel from your laptop:**
```bash
ssh -L 9009:localhost:9009 user@<server-ip>
```
Then open `http://localhost:9009` in your local browser.

---

## Troubleshooting

### `dbt deps` fails during `docker compose build`

The build needs internet access to download dbt packages from dbt Hub. Check
that the server has outbound HTTPS access, or pre-download the packages and
`COPY` them in.

### Rill can't read the DuckDB file

The Rill connector uses:
```yaml
init_sql: "ATTACH '../data/vegan_basket.duckdb' AS vb (READ_ONLY);"
```
This resolves relative to the Rill project directory (`/app/rill`), so it
looks for `/app/data/vegan_basket.duckdb`. Confirm the volume is mounted:
```bash
docker compose exec rill ls /app/data/
```

### Pipeline and Rill accessing DuckDB simultaneously

DuckDB allows **multiple concurrent readers but only one writer**. The pipeline
container opens DuckDB in write mode for a few seconds during ingestion; the
Rill container opens it read-only. In practice this is fine for a nightly
batch, but if you see locking errors in the Rill logs during an active
pipeline run, it is expected and transient.

### Cron job not running

1. Check the entrypoint exported env vars correctly:
   ```bash
   docker compose exec pipeline cat /etc/environment
   ```
2. Check the cron log:
   ```bash
   docker compose exec pipeline tail -20 /var/log/syslog
   ```
3. Verify the crontab was registered:
   ```bash
   docker compose exec pipeline cat /etc/cron.d/vegan-basket
   ```

### Telegram alerts not working

Test from inside the container:
```bash
docker compose exec pipeline python -m src.telegram_digest --dry-run
```

---

## File Layout Added by This PR

```
.dockerignore
Dockerfile                    ← pipeline image
Dockerfile.rill               ← Rill dashboard image
docker-compose.yml
scripts/entrypoint.sh         ← exports env vars → starts cron
deploy/
  docker/
    README.md                 ← this file
```
