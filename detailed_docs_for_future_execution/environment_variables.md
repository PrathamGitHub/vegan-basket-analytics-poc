# Environment Variables

Configuration for Vegan Basket Analytics is loaded from environment variables (via `.env` locally, or CI/CD secrets in production).

Copy the template before first run:

```bash
cp .env.example .env
```

## Application

| Variable | Required | Default | Description |
|---|---|---|---|
| `APP_ENV` | No | `local` | Environment name (`local`, `dev`, `ci`, `prod`) |
| `LOG_LEVEL` | No | `INFO` | Logging level: `DEBUG`, `INFO`, `WARNING`, `ERROR` |
| `LOG_FORMAT` | No | `console` | `console` for human-readable output; `json` for structured logs |
| `TIMEZONE` | No | `Asia/Kolkata` | Business timezone per ADR-014 and business rules |

## Paths

| Variable | Required | Default | Description |
|---|---|---|---|
| `DATA_DIR` | No | `./data` | Root directory for local data artifacts |
| `DUCKDB_PATH` | No | `./data/warehouse.duckdb` | DuckDB database file path |
| `DBT_PROJECT_DIR` | No | `./dbt` | dbt project directory |
| `DBT_PROFILES_DIR` | No | `./dbt` | dbt profiles directory |
| `RILL_PROJECT_DIR` | No | `./rill` | Rill project directory |

## Google Sheets (Ingestion)

| Variable | Required | Default | Description |
|---|---|---|---|
| `GOOGLE_SHEET_ID` | No | Documented sheet ID | Google Sheet containing Transaction Log and rate tabs |
| `GOOGLE_SERVICE_ACCOUNT_FILE` | Yes* | `./credentials/service-account.json` | Path to service account JSON key |

\* Required when running live ingestion; not needed for lint/test/dry-run.

See [google_sheets_setup.md](./google_sheets_setup.md) for creating the service account, placing the JSON key, sharing the sheet, and verifying API access.

Sheet tab names (case-sensitive):

- `Transaction Log`
- `Vendor Rates`
- `Customer Rates`

## dlt

| Variable | Required | Default | Description |
|---|---|---|---|
| `DLT_PIPELINE_NAME` | No | `vegan_basket` | dlt pipeline identifier |
| `DLT_DATASET_NAME` | No | `raw` | dlt dataset/schema name in DuckDB |

## Rill

| Variable | Required | Default | Description |
|---|---|---|---|
| `RILL_PORT` | No | `9009` | Host port mapped to Rill in Docker Compose |

## dbt

dbt reads `DUCKDB_PATH` from the environment via `profiles.yml`:

```yaml
path: "{{ env_var('DUCKDB_PATH', '../data/warehouse.duckdb') }}"
```

Set explicitly when running dbt outside Make:

```bash
export DUCKDB_PATH=./data/warehouse.duckdb
export DBT_PROFILES_DIR=./dbt
dbt run --project-dir dbt --profiles-dir dbt
```

## Docker Compose

Docker Compose loads variables from `.env` automatically. Key mappings:

| Compose | Source |
|---|---|
| `env_file: .env` | All application variables |
| `ports: ${RILL_PORT:-9009}:9009` | Rill port |
| Volume `./credentials:/app/credentials:ro` | Service account mount |

## CI (GitHub Actions)

CI sets minimal variables inline:

- Copies `.env.example` to `.env`
- Copies `dbt/profiles.yml.example` to `dbt/profiles.yml`
- Creates empty `data/` and `credentials/` directories

No secrets are required for foundation CI jobs.

## Security Notes

- Never commit `.env` or service account JSON files
- `.gitignore` excludes `.env`, `credentials/*.json`, and `data/*.duckdb`
- Use read-only Google Sheet sharing for the service account
- In production, inject secrets via your deployment platform's secret store

## Example `.env` for Local Development

```bash
APP_ENV=local
LOG_LEVEL=DEBUG
LOG_FORMAT=console
TIMEZONE=Asia/Kolkata

DATA_DIR=./data
DUCKDB_PATH=./data/warehouse.duckdb
DBT_PROJECT_DIR=./dbt
DBT_PROFILES_DIR=./dbt
RILL_PROJECT_DIR=./rill

GOOGLE_SHEET_ID=1hY17FV_LLYVDLe1zKAaVVV4GkyIrZ1GXMbeeL65mLRI
GOOGLE_SERVICE_ACCOUNT_FILE=./credentials/service-account.json

DLT_PIPELINE_NAME=vegan_basket
DLT_DATASET_NAME=raw

RILL_PORT=9009
```
