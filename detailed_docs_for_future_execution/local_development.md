# Local Development Guide

This guide covers day-to-day development for Vegan Basket Analytics on a local machine.

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Python | 3.12 | Required by `pyproject.toml` |
| Make | any recent | Runs project targets |
| Docker | 24+ | Optional; used for parity with CI |
| Docker Compose | v2 | `docker compose` subcommand |
| Git | 2.x | Version control |
| Rill CLI | latest | Only needed when building dashboards |

## First-Time Setup

```bash
git clone <repository-url>
cd vegan-basket-analytics

# Automated setup
make setup

# Or use the setup script
bash scripts/setup.sh
```

This will:

1. Create a Python 3.12 virtual environment in `.venv`
2. Install the project in editable mode with dev dependencies
3. Copy `.env.example` → `.env` (if missing)
4. Copy `dbt/profiles.yml.example` → `dbt/profiles.yml` (if missing)
5. Create `data/` and `credentials/` directories
6. Install pre-commit hooks

Activate the virtual environment:

```bash
source .venv/bin/activate
```

## Environment Configuration

See [environment_variables.md](./environment_variables.md) for the full reference.

Minimum for local development:

```bash
cp .env.example .env
```

Google Sheets credentials are **not** required for linting, testing, or the pipeline dry-run. When you are ready for live ingestion, follow [google_sheets_setup.md](./google_sheets_setup.md).

## Daily Workflow

```bash
# Activate venv
source .venv/bin/activate

# Run pre-commit on staged files (also runs automatically on commit)
pre-commit run --all-files

# Lint
make lint

# Test
make test

# Validate pipeline config (no ingestion yet)
make pipeline

# Run dbt foundation model
make dbt-run
```

## Docker Development

Use Docker when you want an environment matching CI without installing Python 3.12 locally.

```bash
cp .env.example .env
docker compose up -d --build
docker compose exec analytics make test
docker compose exec analytics make lint
docker compose exec analytics make dbt-run
```

Stop containers:

```bash
docker compose down
```

## Project Layout for Developers

| Path | Purpose |
|---|---|
| `pipelines/` | Python package: config, logging, future dlt ingestion |
| `pipelines/config.py` | Settings loaded from `.env` |
| `pipelines/logging_config.py` | structlog setup |
| `pipelines/cli.py` | Pipeline CLI entry point |
| `pipelines/deletion.py` | Orchestrates snapshot diff + staging soft-delete |
| `pipelines/identity.py` | Content-based `source_row_id` generation |
| `pipelines/snapshot.py` | `etl_source_snapshot` persistence and diffing |
| `dbt/models/` | dbt SQL models (empty except foundation placeholder) |
| `dbt/seeds/` | Static seed data (e.g. `dim_product` — not yet added) |
| `tests/` | Pytest tests |
| `data/` | Local DuckDB file (`warehouse.duckdb`) |
| `credentials/` | Google service account JSON (gitignored) |

## dbt Development

Profiles are stored in `dbt/profiles.yml` (gitignored). The example file uses DuckDB:

```yaml
path: "{{ env_var('DUCKDB_PATH', '../data/warehouse.duckdb') }}"
```

Run models:

```bash
export DUCKDB_PATH=./data/warehouse.duckdb
make dbt-run
```

Debug connection:

```bash
.venv/bin/dbt debug --project-dir dbt --profiles-dir dbt
```

## Rill Dashboards

Rill is configured in `rill/rill.yaml` but dashboards are deferred until mart models exist.

Install Rill CLI from [Rill docs](https://docs.rilldata.com/install), then:

```bash
cd rill
rill start
```

Or use `make dashboard` for instructions.

## Pre-commit Hooks

Installed by `make setup`. Hooks run:

- trailing whitespace / EOF fixer
- YAML validation
- large file check
- Ruff lint + format

Run manually:

```bash
pre-commit run --all-files
```

## Troubleshooting

### Python 3.12 not found

Install Python 3.12 or set `PYTHON=python3.12` when running Make targets:

```bash
PYTHON=/usr/bin/python3.12 make setup
```

### dbt profile not found

```bash
cp dbt/profiles.yml.example dbt/profiles.yml
```

### Docker healthcheck fails

Ensure `.env` exists:

```bash
cp .env.example .env
docker compose up -d --build
```

### Import errors in tests

Confirm `PYTHONPATH=.` (Make sets this automatically) and the venv is activated.

## What Not to Implement Locally (Yet)

Do not add business classification or mart logic until ingestion is wired. Refer to `docs/` as the source of truth for:

- Transaction classification
- Rate lookup
- DQ rules and quarantine
- Mart metrics
