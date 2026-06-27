from __future__ import annotations

import logging
import sys

import dlt
import duckdb

from src.config import get_settings
from src.resources import google_sheets_source, load_all_sheets
from src.revision_guard import (
    get_current_row_counts,
    load_stored_counts,
    save_counts,
    sheets_unchanged,
)

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
logger = logging.getLogger(__name__)


def _validate_credentials(settings) -> None:
    credentials_path = settings.google_service_account_file
    if not credentials_path.exists():
        raise FileNotFoundError(
            f"Service account file not found: {credentials_path}. "
            "Place your JSON key at this path or update GOOGLE_SERVICE_ACCOUNT_FILE."
        )
    if credentials_path.stat().st_size == 0:
        raise ValueError(f"Service account file is empty: {credentials_path}")


def _validate_table_counts(
    duckdb_path,
    dataset_name: str,
    source_counts: dict[str, int],
) -> None:
    connection = duckdb.connect(str(duckdb_path))
    try:
        for table_name, source_count in source_counts.items():
            loaded_count = connection.execute(
                f"SELECT COUNT(*) FROM {dataset_name}.{table_name}"
            ).fetchone()[0]
            logger.info(
                "%s.%s: source=%s loaded=%s",
                dataset_name,
                table_name,
                source_count,
                loaded_count,
            )
            if loaded_count != source_count:
                raise RuntimeError(
                    f"Row count mismatch for {dataset_name}.{table_name}: "
                    f"expected {source_count}, got {loaded_count}"
                )
    finally:
        connection.close()


def run_pipeline() -> None:
    settings = get_settings()
    _validate_credentials(settings)

    # --- Revision guard: skip if no new rows since last successful run ---
    credentials_path = str(settings.google_service_account_file)
    current_counts = get_current_row_counts(settings.google_sheet_id, credentials_path)
    stored_counts = load_stored_counts(settings.ingest_state_path)
    if sheets_unchanged(current_counts, stored_counts):
        return

    settings.duckdb_path.parent.mkdir(parents=True, exist_ok=True)
    sheet_data = load_all_sheets(settings)
    source_counts = {
        name: data.source_row_count for name, data in sheet_data.items()
    }

    pipeline = dlt.pipeline(
        pipeline_name=settings.dlt_pipeline_name,
        destination=dlt.destinations.duckdb(str(settings.duckdb_path)),
        dataset_name=settings.dlt_dataset_name,
    )

    logger.info("Running ingestion into %s", settings.duckdb_path)
    load_info = pipeline.run(google_sheets_source(sheet_data))
    logger.info("Load completed: %s", load_info)

    _validate_table_counts(
        settings.duckdb_path,
        settings.dlt_dataset_name,
        source_counts,
    )
    logger.info("Validation passed for all raw tables.")

    save_counts(settings.ingest_state_path, current_counts)


def main() -> None:
    try:
        run_pipeline()
    except Exception as exc:
        logger.error("Pipeline failed: %s", exc)
        sys.exit(1)


if __name__ == "__main__":
    main()
