from __future__ import annotations

from typing import Any, Iterator

import dlt

from src.config import (
    CUSTOMER_RATES_COLUMN_MAP,
    SHEET_TAB_CUSTOMER_RATES,
    SHEET_TAB_TRANSACTION_LOG,
    SHEET_TAB_VENDOR_RATES,
    TRANSACTION_LOG_COLUMN_MAP,
    VENDOR_RATES_COLUMN_MAP,
    Settings,
    get_settings,
)
from src.sheets_client import SheetData, fetch_sheet_tab


def load_all_sheets(settings: Settings | None = None) -> dict[str, SheetData]:
    settings = settings or get_settings()
    credentials_path = str(settings.google_service_account_file)
    sheet_id = settings.google_sheet_id

    return {
        "transaction_log": fetch_sheet_tab(
            sheet_id=sheet_id,
            tab_name=SHEET_TAB_TRANSACTION_LOG,
            column_map=TRANSACTION_LOG_COLUMN_MAP,
            credentials_path=credentials_path,
        ),
        "vendor_rates": fetch_sheet_tab(
            sheet_id=sheet_id,
            tab_name=SHEET_TAB_VENDOR_RATES,
            column_map=VENDOR_RATES_COLUMN_MAP,
            credentials_path=credentials_path,
        ),
        "customer_rates": fetch_sheet_tab(
            sheet_id=sheet_id,
            tab_name=SHEET_TAB_CUSTOMER_RATES,
            column_map=CUSTOMER_RATES_COLUMN_MAP,
            credentials_path=credentials_path,
        ),
    }


@dlt.source
def google_sheets_source(sheet_data: dict[str, SheetData]):
    @dlt.resource(name="transaction_log", write_disposition="replace")
    def transaction_log() -> Iterator[dict[str, Any]]:
        yield from sheet_data["transaction_log"].rows

    @dlt.resource(name="vendor_rates", write_disposition="replace")
    def vendor_rates() -> Iterator[dict[str, Any]]:
        yield from sheet_data["vendor_rates"].rows

    @dlt.resource(name="customer_rates", write_disposition="replace")
    def customer_rates() -> Iterator[dict[str, Any]]:
        yield from sheet_data["customer_rates"].rows

    return transaction_log, vendor_rates, customer_rates
