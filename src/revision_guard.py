"""
Pre-flight guard for the daily ingestion pipeline.

Fetches only column A of each sheet tab (a single lightweight API call per
tab) to count data rows, then compares against the counts stored after the
previous successful run.  If all counts are identical the pipeline can skip
the dlt load and DuckDB write entirely, saving quota and I/O.

This uses only the existing `spreadsheets.readonly` scope — no Drive API or
extra permissions required.

Set the env var FORCE_RUN=true to bypass the guard and always run.
"""
from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Any

from google.oauth2 import service_account
from googleapiclient.discovery import build

logger = logging.getLogger(__name__)

_SCOPES = ["https://www.googleapis.com/auth/spreadsheets.readonly"]

# Maps our internal table names to the actual Google Sheet tab titles.
_TAB_NAMES: dict[str, str] = {
    "transaction_log": "Transaction Log",
    "vendor_rates": "Vendor Rates",
    "customer_rates": "Customer Rates",
}


def _build_service(credentials_path: str):
    creds = service_account.Credentials.from_service_account_file(
        credentials_path, scopes=_SCOPES
    )
    return build("sheets", "v4", credentials=creds, cache_discovery=False)


def _count_tab_rows(service, sheet_id: str, tab_name: str) -> int:
    """Return the number of data rows (header excluded) by fetching column A only."""
    result = (
        service.spreadsheets()
        .values()
        .get(
            spreadsheetId=sheet_id,
            range=f"'{tab_name}'!A:A",
            majorDimension="COLUMNS",
        )
        .execute()
    )
    columns = result.get("values", [])
    if not columns:
        return 0
    return max(0, len(columns[0]) - 1)


def get_current_row_counts(sheet_id: str, credentials_path: str) -> dict[str, int]:
    """Return {table_name: data_row_count} using one lightweight API call per tab."""
    service = _build_service(credentials_path)
    counts = {
        key: _count_tab_rows(service, sheet_id, tab_name)
        for key, tab_name in _TAB_NAMES.items()
    }
    logger.info("Current sheet row counts: %s", counts)
    return counts


def load_stored_counts(state_path: Path) -> dict[str, int] | None:
    """Return row counts from the last successful run, or None if no state exists."""
    if not state_path.exists():
        logger.info("No state file at %s — treating as first run.", state_path)
        return None
    try:
        data: dict[str, Any] = json.loads(state_path.read_text())
        counts = data.get("row_counts")
        if isinstance(counts, dict):
            return {str(k): int(v) for k, v in counts.items()}
    except (json.JSONDecodeError, OSError, ValueError):
        logger.warning(
            "State file %s is unreadable — will run pipeline.", state_path
        )
    return None


def save_counts(state_path: Path, counts: dict[str, int]) -> None:
    """Persist row counts after a successful pipeline run."""
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(json.dumps({"row_counts": counts}, indent=2))
    logger.info("Ingestion state saved → %s", state_path)


def is_force_run() -> bool:
    return os.getenv("FORCE_RUN", "false").strip().lower() in ("1", "true", "yes")


def sheets_unchanged(
    current: dict[str, int],
    stored: dict[str, int] | None,
) -> bool:
    """Return True iff all tab row counts match the stored state (and FORCE_RUN is unset)."""
    if is_force_run():
        logger.info("FORCE_RUN=true — bypassing revision guard.")
        return False
    if stored is None:
        return False
    if current == stored:
        logger.info(
            "Sheet row counts unchanged %s — no new data, skipping run.", current
        )
        return True
    changed = {
        k: {"before": stored.get(k, 0), "after": v}
        for k, v in current.items()
        if stored.get(k) != v
    }
    logger.info("Changes detected in tabs: %s — proceeding with pipeline.", changed)
    return False
