#!/usr/bin/env bash
# Reconcile Rill dashboard KPI definitions against DuckDB mart tables.
# Usage: ./scripts/reconcile_rill_metrics.sh [start_date] [end_date]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB="${DUCKDB_PATH:-$ROOT/data/vegan_basket.duckdb}"
START_DATE="${1:-2026-01-01}"
END_DATE="${2:-2026-12-31}"

if [[ ! -f "$DB" ]]; then
  echo "DuckDB file not found: $DB" >&2
  exit 1
fi

run_query() {
  duckdb -readonly "$DB" -c "$1"
}

echo "Reconciling KPIs for date range ${START_DATE} to ${END_DATE}"
echo "Database: ${DB}"
echo

run_query "
WITH filtered AS (
  SELECT *
  FROM marts.mart_daily_metrics
  WHERE date BETWEEN DATE '${START_DATE}' AND DATE '${END_DATE}'
)
SELECT
  'purchase_qty' AS metric,
  ROUND(SUM(purchase_qty), 3) AS duckdb_value
FROM filtered
UNION ALL
SELECT 'purchase_amount', ROUND(SUM(purchase_amount), 2) FROM filtered
UNION ALL
SELECT 'sales_qty', ROUND(SUM(sales_qty), 3) FROM filtered
UNION ALL
SELECT 'sales_amount', ROUND(SUM(sales_amount), 2) FROM filtered
UNION ALL
SELECT 'payments_paid', ROUND(SUM(payments_paid), 2) FROM filtered
UNION ALL
SELECT 'payments_received', ROUND(SUM(payments_received), 2) FROM filtered
UNION ALL
SELECT 'outstanding_payable', ROUND(arg_max(outstanding_payable, date), 2) FROM filtered
UNION ALL
SELECT 'outstanding_receivable', ROUND(arg_max(outstanding_receivable, date), 2) FROM filtered
ORDER BY metric;
"

echo
echo "Vendor outstanding (lifetime, filter by vendor in Rill):"
run_query "
SELECT
  ROUND(SUM(outstanding_payable), 2) AS total_outstanding_payable
FROM marts.mart_vendor_summary;
"

echo
echo "Customer outstanding (lifetime, filter by customer in Rill):"
run_query "
SELECT
  ROUND(SUM(outstanding_receivable), 2) AS total_outstanding_receivable
FROM marts.mart_customer_summary;
"

echo
echo "Compare these values to the Rill dashboard KPIs for the same date range."
