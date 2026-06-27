from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv
import os

load_dotenv()

SHEET_TAB_TRANSACTION_LOG = "Transaction Log"
SHEET_TAB_VENDOR_RATES = "Vendor Rates"
SHEET_TAB_CUSTOMER_RATES = "Customer Rates"

TRANSACTION_LOG_COLUMN_MAP: dict[str, str] = {
    "Timestamp": "timestamp",
    "Transaction Date (if not same as today)": "transaction_date",
    "Transaction Type": "transaction_type",
    "Vendor Name": "vendor_name",
    "Customer Name": "customer_name",
    "Payment (Rs)": "payment_rs",
    "Payment Mode": "payment_mode",
    "Mushroom Bulk Qty (kg)": "mushroom_bulk_qty_kg",
    "Mushroom Pannet Qty (kg)": "mushroom_pannet_qty_kg",
    "Mushroom B Grade Qty (kg)": "mushroom_b_grade_qty_kg",
    "Baby Corn Qty (kg)": "baby_corn_qty_kg",
    "Lahsun Qty (kg)": "lahsun_qty_kg",
    "Remarks": "remarks",
}

VENDOR_RATES_COLUMN_MAP: dict[str, str] = {
    "Effective From Date": "effective_from",
    "Vendor Name": "vendor_name",
    "Mushroom Bulk Rate (Rs)": "mushroom_bulk_rate_rs",
    "Mushroom Pannet Rate (Rs)": "mushroom_pannet_rate_rs",
    "Mushroom B Grade Rate (Rs)": "mushroom_b_grade_rate_rs",
    "Baby Corn Rate (Rs)": "baby_corn_rate_rs",
    "Lahsun Rate (Rs)": "lahsun_rate_rs",
    "Remarks": "remarks",
}

CUSTOMER_RATES_COLUMN_MAP: dict[str, str] = {
    "Effective From Date": "effective_from",
    "Customer Name": "customer_name",
    "Mushroom Bulk Rate (Rs)": "mushroom_bulk_rate_rs",
    "Mushroom Pannet Rate (Rs)": "mushroom_pannet_rate_rs",
    "Mushroom B Grade Rate (Rs)": "mushroom_b_grade_rate_rs",
    "Baby Corn Rate (Rs)": "baby_corn_rate_rs",
    "Lahsun Rate (Rs)": "lahsun_rate_rs",
    "Remarks": "remarks",
}


@dataclass(frozen=True)
class Settings:
    google_sheet_id: str
    google_service_account_file: Path
    duckdb_path: Path
    dlt_pipeline_name: str
    dlt_dataset_name: str
    ingest_state_path: Path


def get_settings() -> Settings:
    project_root = Path(__file__).resolve().parent.parent
    service_account_file = Path(
        os.getenv("GOOGLE_SERVICE_ACCOUNT_FILE", "./credentials/service-account.json")
    )
    if not service_account_file.is_absolute():
        service_account_file = project_root / service_account_file

    duckdb_path = Path(os.getenv("DUCKDB_PATH", "./data/vegan_basket.duckdb"))
    if not duckdb_path.is_absolute():
        duckdb_path = project_root / duckdb_path

    ingest_state_path = Path(
        os.getenv("INGEST_STATE_PATH", "./data/ingest_state.json")
    )
    if not ingest_state_path.is_absolute():
        ingest_state_path = project_root / ingest_state_path

    google_sheet_id = os.getenv("GOOGLE_SHEET_ID", "").strip()
    if not google_sheet_id:
        raise ValueError("GOOGLE_SHEET_ID is required in .env")

    return Settings(
        google_sheet_id=google_sheet_id,
        google_service_account_file=service_account_file,
        duckdb_path=duckdb_path,
        dlt_pipeline_name=os.getenv("DLT_PIPELINE_NAME", "vegan_basket"),
        dlt_dataset_name=os.getenv("DLT_DATASET_NAME", "raw"),
        ingest_state_path=ingest_state_path,
    )
