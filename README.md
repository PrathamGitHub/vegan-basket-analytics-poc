# Vegan Basket Analytics — Phase 1

Minimal ingestion pipeline: **Google Sheets → dlt → DuckDB**.

Loads three worksheets into the `raw` schema with full replace on every run.

| Google Sheet tab   | DuckDB table              |
|--------------------|---------------------------|
| Transaction Log    | `raw.transaction_log`     |
| Vendor Rates       | `raw.vendor_rates`        |
| Customer Rates     | `raw.customer_rates`      |

## Prerequisites

- Python 3.12
- Google Cloud service account with **Google Sheets API** enabled
- Operational sheet shared with the service account email (Viewer)

See `detailed_docs_for_future_execution/google_sheets_setup.md` for credential setup.

## Setup

```bash
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
# Edit .env with your GOOGLE_SHEET_ID

mkdir -p credentials
# Place service account JSON at credentials/service-account.json
```

## Run

From the project root:

```bash
source .venv/bin/activate
python -m src.pipeline
```

This will:

1. Read all three sheet tabs via the Google Sheets API
2. Map headers to snake_case column names
3. Load data into `./data/vegan_basket.duckdb` using `write_disposition="replace"`
4. Validate row counts match the sheet (excluding header and blank rows)

## Verify

```bash
duckdb data/vegan_basket.duckdb -c "SELECT COUNT(*) FROM raw.transaction_log"
duckdb data/vegan_basket.duckdb -c "SELECT COUNT(*) FROM raw.vendor_rates"
duckdb data/vegan_basket.duckdb -c "SELECT COUNT(*) FROM raw.customer_rates"
```

Or in Python:

```python
import duckdb
conn = duckdb.connect("data/vegan_basket.duckdb")
print(conn.execute("SELECT * FROM raw.transaction_log LIMIT 5").fetchdf())
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `GOOGLE_SHEET_ID` | *(required)* | Spreadsheet ID from the sheet URL |
| `GOOGLE_SERVICE_ACCOUNT_FILE` | `./credentials/service-account.json` | Path to service account JSON |
| `DUCKDB_PATH` | `./data/vegan_basket.duckdb` | Output database file |
| `DLT_PIPELINE_NAME` | `vegan_basket` | dlt pipeline name |
| `DLT_DATASET_NAME` | `raw` | DuckDB schema name |

## Project layout

```
src/
├── config.py          # Environment settings and column mappings
├── sheets_client.py   # Google Sheets API client
├── resources.py       # dlt source and resources
└── pipeline.py        # Entry point (python -m src.pipeline)
data/
└── vegan_basket.duckdb   # Created on first successful run
```

## Out of scope (Phase 1)

- Incremental loading, merge, primary keys, deduplication
- Staging transforms, dbt models, data quality rules
- Soft-delete / snapshot diffing

These are documented in `detailed_docs_for_future_execution/` for later phases.
