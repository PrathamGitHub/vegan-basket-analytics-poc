#!/usr/bin/env bash
# Start the Vegan Basket Rill dashboard (run from repo root or anywhere).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/rill"

if [[ ! -f "$ROOT/data/vegan_basket.duckdb" ]]; then
  echo "DuckDB not found. Run dbt first: export DUCKDB_PATH=$ROOT/data/vegan_basket.duckdb && dbt run --project-dir dbt --profiles-dir dbt" >&2
  exit 1
fi

echo "Starting Rill at http://localhost:9009 (production / preview mode)"
echo "Open dashboard: Vegan Basket Operations"
exec rill start --model-timeout-seconds 180 --preview --environment production
