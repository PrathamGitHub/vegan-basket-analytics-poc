from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from google.oauth2 import service_account
from googleapiclient.discovery import build

SCOPES = ["https://www.googleapis.com/auth/spreadsheets.readonly"]


@dataclass(frozen=True)
class SheetData:
    tab_name: str
    rows: list[dict[str, Any]]
    source_row_count: int


def _is_empty_row(values: list[str]) -> bool:
    return not any(str(value).strip() for value in values)


def _build_service(credentials_path: str):
    credentials = service_account.Credentials.from_service_account_file(
        credentials_path,
        scopes=SCOPES,
    )
    return build("sheets", "v4", credentials=credentials, cache_discovery=False)


def fetch_sheet_tab(
    *,
    sheet_id: str,
    tab_name: str,
    column_map: dict[str, str],
    credentials_path: str,
) -> SheetData:
    service = _build_service(credentials_path)
    result = (
        service.spreadsheets()
        .values()
        .get(
            spreadsheetId=sheet_id,
            range=f"'{tab_name}'",
            valueRenderOption="FORMATTED_VALUE",
            dateTimeRenderOption="FORMATTED_STRING",
        )
        .execute()
    )

    values = result.get("values", [])
    if not values:
        return SheetData(tab_name=tab_name, rows=[], source_row_count=0)

    headers = [str(header).strip() for header in values[0]]
    unknown_headers = [header for header in headers if header and header not in column_map]
    if unknown_headers:
        raise ValueError(
            f"Unrecognized columns in '{tab_name}': {', '.join(unknown_headers)}"
        )

    header_indexes = {
        index: column_map[header]
        for index, header in enumerate(headers)
        if header in column_map
    }

    rows: list[dict[str, Any]] = []
    for row_values in values[1:]:
        padded = row_values + [""] * (len(headers) - len(row_values))
        if _is_empty_row(padded):
            continue

        record: dict[str, Any] = {}
        for index, target_name in header_indexes.items():
            value = padded[index] if index < len(padded) else ""
            record[target_name] = str(value).strip() if value is not None else ""
        rows.append(record)

    return SheetData(tab_name=tab_name, rows=rows, source_row_count=len(rows))
