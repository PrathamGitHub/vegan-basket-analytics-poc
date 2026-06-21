# Google Sheets Setup

> **Status:** Operational — required for live ingestion
> **Last updated:** 2026-06-21
> **Related:** [environment_variables.md](./environment_variables.md), [architecture_decisions.md](./architecture_decisions.md) (ADR-011)

This guide walks through creating a Google Cloud service account, placing credentials locally, sharing the operational sheet, and verifying API access.

---

## Overview

The pipeline reads three worksheets from a single Google Sheet via the **Google Sheets API v4** using **service account** authentication (ADR-011):

| Worksheet | Staging target |
|---|---|
| `Transaction Log` | `stg_transaction_log` |
| `Vendor Rates` | `stg_vendor_rates` |
| `Customer Rates` | `stg_customer_rates` |

Tab names are **case-sensitive** and defined in `pipelines/constants.py`.

---

## Prerequisites

- Access to [Google Cloud Console](https://console.cloud.google.com/) (ability to create projects and service accounts)
- **Editor** or **Owner** access to the operational Google Sheet
- Local project setup complete (`make setup`, `.env` present)

Google Sheets credentials are **not** required for linting, testing, or the pipeline dry-run.

---

## 1. Configure environment variables

Copy the template if you have not already:

```bash
cp .env.example .env
```

Ensure these variables are set (defaults are provided in `.env.example`):

| Variable | Description |
|---|---|
| `GOOGLE_SHEET_ID` | Spreadsheet ID from the sheet URL |
| `GOOGLE_SERVICE_ACCOUNT_FILE` | Path to the service account JSON key |

Example `.env` entries:

```bash
GOOGLE_SHEET_ID=google_sheet_id_here
GOOGLE_SERVICE_ACCOUNT_FILE=./credentials/service-account.json
```

The sheet ID is the long string in the URL:

```
https://docs.google.com/spreadsheets/d/{GOOGLE_SHEET_ID}/edit
```

Settings are loaded by `pipelines/config.py` at runtime.

---

## 2. Create a Google Cloud service account

### 2.1 Create or select a project

1. Open [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one (e.g. `vegan-basket-analytics`)

### 2.2 Enable the Google Sheets API

1. Go to **APIs & Services → Library**
2. Search for **Google Sheets API**
3. Click **Enable**

### 2.3 Create the service account

1. Go to **IAM & Admin → Service Accounts**
2. Click **Create Service Account**
3. Name: e.g. `vegan-basket-sheets-reader`
4. Description (optional): read-only access to the operational sheet
5. Click **Create and Continue**
6. Skip optional IAM role assignment (sheet sharing grants access) and click **Done**

### 2.4 Download a JSON key

1. Open the service account you just created
2. Go to the **Keys** tab
3. Click **Add Key → Create new key → JSON**
4. Save the downloaded file — you will place it in the project in the next step

The JSON contains a `client_email` field (e.g. `vegan-basket-sheets-reader@your-project.iam.gserviceaccount.com`). You need this email to share the sheet.

---

## 3. Place credentials locally

The `credentials/` directory is created by `make setup` and is gitignored.

```bash
mkdir -p credentials
cp ~/Downloads/your-downloaded-key.json credentials/service-account.json
```

Expected file layout:

```
credentials/
└── service-account.json    # gitignored — never commit
```

The JSON should include at minimum:

```json
{
  "type": "service_account",
  "project_id": "your-gcp-project",
  "client_email": "your-sa@your-project.iam.gserviceaccount.com",
  "client_id": "...",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token"
}
```

Google also includes `private_key_id` and `private_key` in the downloaded file. Do not paste or commit those values — use the file from Cloud Console as-is.

If the file is empty or invalid, ingestion will fail at runtime.

---

## 4. Share the Google Sheet

Service accounts do not inherit your personal Google Drive access. You must share the sheet explicitly.

1. Open the operational spreadsheet
2. Click **Share**
3. Add the **`client_email`** from `credentials/service-account.json`
4. Set permission to **Viewer** (read-only is sufficient)

Confirm the three expected tabs exist with exact names:

- `Transaction Log`
- `Vendor Rates`
- `Customer Rates`

---

## 5. Verify access

From the project root with the virtual environment activated:

```bash
source .venv/bin/activate

python - <<'EOF'
import json
from google.oauth2 import service_account
from googleapiclient.discovery import build

from pipelines.config import get_settings
from pipelines.constants import (
    SHEET_TAB_CUSTOMER_RATES,
    SHEET_TAB_TRANSACTION_LOG,
    SHEET_TAB_VENDOR_RATES,
)

settings = get_settings()
creds_path = settings.google_service_account_file

if not creds_path.exists() or creds_path.stat().st_size == 0:
    raise SystemExit(f"Missing or empty credentials file: {creds_path}")

with creds_path.open() as f:
    info = json.load(f)
print(f"Service account: {info['client_email']}")
print(f"Sheet ID: {settings.google_sheet_id}")

creds = service_account.Credentials.from_service_account_file(
    str(creds_path),
    scopes=["https://www.googleapis.com/auth/spreadsheets.readonly"],
)
service = build("sheets", "v4", credentials=creds, cache_discovery=False)

for tab in (SHEET_TAB_TRANSACTION_LOG, SHEET_TAB_VENDOR_RATES, SHEET_TAB_CUSTOMER_RATES):
    result = (
        service.spreadsheets()
        .values()
        .get(
            spreadsheetId=settings.google_sheet_id,
            range=f"'{tab}'!A1:Z1",
        )
        .execute()
    )
    headers = result.get("values", [[]])[0]
    print(f"  OK  {tab!r} — {len(headers)} columns in header row")

print("\nGoogle Sheets access verified.")
EOF
```

Expected output:

```
Service account: your-sa@your-project.iam.gserviceaccount.com
Sheet ID: 1hY17FV_...
  OK  'Transaction Log' — N columns in header row
  OK  'Vendor Rates' — N columns in header row
  OK  'Customer Rates' — N columns in header row

Google Sheets access verified.
```

---

## 6. Docker usage

Docker Compose mounts `./credentials` read-only into the container:

```yaml
volumes:
  - ./credentials:/app/credentials:ro
```

Ensure `credentials/service-account.json` exists on the host before starting containers. The same `.env` values apply inside Docker.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `403 Permission denied` | Sheet not shared with service account | Share sheet with `client_email` as Viewer |
| `404 Not found` | Wrong `GOOGLE_SHEET_ID` | Copy ID from the sheet URL into `.env` |
| `Unable to parse range` | Tab name mismatch | Rename tab or update `pipelines/constants.py` |
| `Missing or empty credentials file` | Key not copied or zero-byte file | Re-download JSON key from Cloud Console |
| `Invalid JSON` | Truncated or edited key file | Replace with a fresh download |
| `API has not been used...` or `403 accessNotConfigured` | Sheets API not enabled | Enable Google Sheets API in Cloud Console |

---

## Security

| Rule | Detail |
|---|---|
| Never commit credentials | `.gitignore` excludes `credentials/` and `*.json` |
| Read-only sheet access | Grant **Viewer** only — the pipeline does not write back |
| Key rotation | Create a new key in Cloud Console, replace the file, delete the old key |
| Production | Inject the JSON via your deployment platform's secret store, not the repo |
| Principle of least privilege | Do not grant GCP IAM roles beyond what ingestion requires |

---

## CI and foundation tests

GitHub Actions CI does **not** require Google credentials. It creates an empty `credentials/` directory and copies `.env.example` to `.env`. Foundation jobs (lint, test, dry-run) run without live sheet access.

Live ingestion tests should be marked `@pytest.mark.integration` and run only when credentials are configured locally.
