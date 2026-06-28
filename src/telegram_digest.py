"""
Daily Telegram digest after ingestion + dbt.

Queries DuckDB marts and sends a Markdown summary to a private bot chat.
Designed to be non-fatal: Telegram failures must not fail the nightly job.
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import duckdb

from src.config import get_settings

logger = logging.getLogger(__name__)

IST = ZoneInfo("Asia/Kolkata")
TELEGRAM_API = "https://api.telegram.org/bot{token}/sendMessage"


@dataclass(frozen=True)
class TelegramSettings:
    enabled: bool
    bot_token: str
    chat_ids: list[str]


@dataclass(frozen=True)
class DailyMetrics:
    report_date: date
    sales_amount: float
    sales_qty: float
    purchase_amount: float
    purchase_qty: float
    payments_received: float
    payments_paid: float
    transaction_count: int
    outstanding_receivable: float
    outstanding_payable: float
    mtd_sales_amount: float
    mtd_purchase_amount: float
    fytd_sales_amount: float
    fytd_purchase_amount: float


@dataclass(frozen=True)
class PipelineStatus:
    skipped: bool
    row_delta: dict[str, int] | None
    finished_at: str | None


def _resolve_chat_ids() -> list[str]:
    """Collect unique recipient IDs from TELEGRAM_CHAT_IDS and TELEGRAM_CHAT_ID.

    Priority / merge rules:
    - TELEGRAM_CHAT_IDS=id1,id2,id3  (comma-separated; primary for multi-recipient)
    - TELEGRAM_CHAT_ID=id            (single ID; original env var kept for compatibility)
    Both are read and deduplicated while preserving order.
    """
    ids: list[str] = []
    seen: set[str] = set()

    multi = os.getenv("TELEGRAM_CHAT_IDS", "")
    for raw in multi.split(","):
        cid = raw.strip()
        if cid and cid not in seen:
            ids.append(cid)
            seen.add(cid)

    single = os.getenv("TELEGRAM_CHAT_ID", "").strip()
    if single and single not in seen:
        ids.append(single)
        seen.add(single)

    return ids


def get_telegram_settings() -> TelegramSettings | None:
    enabled = os.getenv("TELEGRAM_DIGEST_ENABLED", "true").strip().lower() in (
        "1",
        "true",
        "yes",
    )
    if not enabled:
        logger.info("Telegram digest disabled (TELEGRAM_DIGEST_ENABLED=false).")
        return None

    token = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
    chat_ids = _resolve_chat_ids()

    if not token or not chat_ids:
        logger.warning(
            "Telegram digest skipped: set TELEGRAM_BOT_TOKEN and at least one of "
            "TELEGRAM_CHAT_IDS or TELEGRAM_CHAT_ID in .env."
        )
        return None

    logger.info("Telegram recipients: %d chat(s) configured.", len(chat_ids))
    return TelegramSettings(enabled=True, bot_token=token, chat_ids=chat_ids)


def _escape_markdown(text: str) -> str:
    special = "_*[]()~`>#+-=|{}.!"
    escaped = []
    for char in text:
        if char == "\\" or char in special:
            escaped.append("\\")
        escaped.append(char)
    return "".join(escaped)


def fmt_rs(amount: float) -> str:
    return f"₹{amount:,.0f}"


def fmt_kg(qty: float) -> str:
    return f"{qty:,.1f} kg"


def fiscal_year_start(report_date: date) -> date:
    if report_date.month >= 4:
        return date(report_date.year, 4, 1)
    return date(report_date.year - 1, 4, 1)


def load_pipeline_status(settings) -> PipelineStatus:
    status_path = settings.ingest_state_path.parent / "last_ingest_run.json"
    if not status_path.exists():
        return PipelineStatus(skipped=False, row_delta=None, finished_at=None)
    try:
        data = json.loads(status_path.read_text())
    except (OSError, json.JSONDecodeError):
        return PipelineStatus(skipped=False, row_delta=None, finished_at=None)

    row_delta = data.get("row_delta")
    if isinstance(row_delta, dict):
        row_delta = {str(k): int(v) for k, v in row_delta.items()}
    else:
        row_delta = None

    return PipelineStatus(
        skipped=bool(data.get("skipped")),
        row_delta=row_delta,
        finished_at=data.get("finished_at"),
    )


def fetch_daily_metrics(duckdb_path: Path, report_date: date) -> DailyMetrics | None:
    if not duckdb_path.exists():
        return None

    month_start = report_date.replace(day=1)
    fy_start = fiscal_year_start(report_date)

    connection = duckdb.connect(str(duckdb_path), read_only=True)
    try:
        daily_row = connection.execute(
            """
            select
                sales_amount,
                sales_qty,
                purchase_amount,
                purchase_qty,
                payments_received,
                payments_paid,
                outstanding_receivable,
                outstanding_payable
            from marts.mart_daily_metrics
            where date = ?
            """,
            [report_date],
        ).fetchone()

        if daily_row is None:
            return None

        balances_row = connection.execute(
            """
            select outstanding_receivable, outstanding_payable
            from marts.mart_daily_metrics
            order by date desc
            limit 1
            """
        ).fetchone()

        mtd_row = connection.execute(
            """
            select
                coalesce(sum(sales_amount), 0),
                coalesce(sum(purchase_amount), 0)
            from marts.mart_daily_metrics
            where date between ? and ?
            """,
            [month_start, report_date],
        ).fetchone()

        fytd_row = connection.execute(
            """
            select
                coalesce(sum(sales_amount), 0),
                coalesce(sum(purchase_amount), 0)
            from marts.mart_daily_metrics
            where date between ? and ?
            """,
            [fy_start, report_date],
        ).fetchone()

        txn_count = connection.execute(
            """
            select count(distinct transaction_key)
            from marts.mart_transactions
            where date = ?
            """,
            [report_date],
        ).fetchone()[0]
    finally:
        connection.close()

    ar, ap = balances_row if balances_row else (daily_row[6], daily_row[7])

    return DailyMetrics(
        report_date=report_date,
        sales_amount=float(daily_row[0] or 0),
        sales_qty=float(daily_row[1] or 0),
        purchase_amount=float(daily_row[2] or 0),
        purchase_qty=float(daily_row[3] or 0),
        payments_received=float(daily_row[4] or 0),
        payments_paid=float(daily_row[5] or 0),
        transaction_count=int(txn_count or 0),
        outstanding_receivable=float(ar or 0),
        outstanding_payable=float(ap or 0),
        mtd_sales_amount=float(mtd_row[0] or 0),
        mtd_purchase_amount=float(mtd_row[1] or 0),
        fytd_sales_amount=float(fytd_row[0] or 0),
        fytd_purchase_amount=float(fytd_row[1] or 0),
    )


def format_runtime_seconds() -> str | None:
    start_raw = os.getenv("INGEST_START_EPOCH", "").strip()
    if not start_raw:
        return None
    try:
        start = int(start_raw)
    except ValueError:
        return None
    elapsed = max(0, int(datetime.now(tz=IST).timestamp()) - start)
    minutes, seconds = divmod(elapsed, 60)
    if minutes:
        return f"{minutes}m {seconds}s"
    return f"{seconds}s"


def format_pipeline_section(status: PipelineStatus) -> str:
    if status.skipped:
        ingest_line = "Ingest: skipped \\(no new sheet rows\\)"
    elif status.row_delta:
        parts = [
            f"{_escape_markdown(table)} \\+{delta}"
            for table, delta in sorted(status.row_delta.items())
        ]
        ingest_line = "Ingest: loaded " + ", ".join(parts)
    else:
        ingest_line = "Ingest: loaded"

    runtime = format_runtime_seconds()
    runtime_line = f"Runtime: {_escape_markdown(runtime)}" if runtime else "Runtime: n/a"
    return f"{ingest_line}\ndbt: OK\n{runtime_line}"


def build_success_message(metrics: DailyMetrics | None, status: PipelineStatus) -> str:
    now = datetime.now(tz=IST)
    header_date = _escape_markdown(now.strftime("%Y-%m-%d"))

    lines = [
        f"📊 *Vegan Basket Daily Digest*",
        f"_{header_date} IST_",
        "",
    ]

    if metrics is None:
        lines.extend(
            [
                "⚠️ *Metrics*",
                "No mart data available yet\\. Run ingestion \\+ dbt first\\.",
                "",
            ]
        )
    else:
        report = _escape_markdown(metrics.report_date.isoformat())
        lines.extend(
            [
                f"📈 *Today* \\({report}\\)",
                f"Sales: {_escape_markdown(fmt_rs(metrics.sales_amount))} "
                f"\\({_escape_markdown(str(metrics.transaction_count))} txn\\) · "
                f"Qty {_escape_markdown(fmt_kg(metrics.sales_qty))}",
                f"Purchases: {_escape_markdown(fmt_rs(metrics.purchase_amount))} · "
                f"Qty {_escape_markdown(fmt_kg(metrics.purchase_qty))}",
                f"Collected: {_escape_markdown(fmt_rs(metrics.payments_received))} · "
                f"Paid: {_escape_markdown(fmt_rs(metrics.payments_paid))}",
                "",
                f"💼 *Overall* \\({report}\\)",
                f"AR: {_escape_markdown(fmt_rs(metrics.outstanding_receivable))} · "
                f"AP: {_escape_markdown(fmt_rs(metrics.outstanding_payable))}",
                f"MTD sales: {_escape_markdown(fmt_rs(metrics.mtd_sales_amount))} · "
                f"MTD purchases: {_escape_markdown(fmt_rs(metrics.mtd_purchase_amount))}",
                f"FYTD sales: {_escape_markdown(fmt_rs(metrics.fytd_sales_amount))} · "
                f"FYTD purchases: {_escape_markdown(fmt_rs(metrics.fytd_purchase_amount))}",
                "",
            ]
        )

    lines.extend(
        [
            "⚙️ *Pipeline*",
            format_pipeline_section(status),
        ]
    )
    return "\n".join(lines)


def build_failure_message(exit_code: int) -> str:
    now = datetime.now(tz=IST).strftime("%Y-%m-%d %H:%M:%S")
    runtime = format_runtime_seconds()
    runtime_text = _escape_markdown(runtime) if runtime else "n/a"
    return (
        f"🚨 *Vegan Basket ingest FAILED*\n"
        f"_{_escape_markdown(now)} IST_\n\n"
        f"Exit code: {_escape_markdown(str(exit_code))}\n"
        f"Runtime before failure: {runtime_text}\n\n"
        f"Check `data/logs/ingest\\-*.log` or "
        f"`journalctl --user -u vegan\\-basket\\-ingest`\\."
    )


def _send_to_one(bot_token: str, chat_id: str, text: str) -> None:
    """Send a single message to one chat ID. Raises RuntimeError on failure."""
    url = TELEGRAM_API.format(token=bot_token)
    payload = urllib.parse.urlencode(
        {
            "chat_id": chat_id,
            "text": text,
            "parse_mode": "MarkdownV2",
            "disable_web_page_preview": "true",
        }
    ).encode()
    request = urllib.request.Request(url, data=payload, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = json.loads(response.read().decode())
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        raise RuntimeError(f"Telegram API HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Telegram API request failed: {exc}") from exc

    if not body.get("ok"):
        raise RuntimeError(f"Telegram API error: {body}")


def broadcast_message(settings: TelegramSettings, text: str) -> int:
    """Send text to every configured chat. Returns the number of failures."""
    failures = 0
    for chat_id in settings.chat_ids:
        try:
            _send_to_one(settings.bot_token, chat_id, text)
            logger.info("Sent to chat %s.", chat_id)
        except RuntimeError as exc:
            logger.error("Failed to send to chat %s: %s", chat_id, exc)
            failures += 1
    return failures


def send_success_digest(*, dry_run: bool = False) -> int:
    settings = get_settings()
    report_date = datetime.now(tz=IST).date()
    metrics = fetch_daily_metrics(settings.duckdb_path, report_date)
    status = load_pipeline_status(settings)
    message = build_success_message(metrics, status)

    if dry_run:
        print(message)
        return 0

    telegram = get_telegram_settings()
    if telegram is None:
        return 0

    failures = broadcast_message(telegram, message)
    sent = len(telegram.chat_ids) - failures
    logger.info("Telegram daily digest: sent to %d/%d chat(s).", sent, len(telegram.chat_ids))
    return 0


def send_failure_alert(exit_code: int, *, dry_run: bool = False) -> int:
    message = build_failure_message(exit_code)
    if dry_run:
        print(message)
        return 0

    telegram = get_telegram_settings()
    if telegram is None:
        return 0

    failures = broadcast_message(telegram, message)
    sent = len(telegram.chat_ids) - failures
    logger.info("Telegram failure alert: sent to %d/%d chat(s).", sent, len(telegram.chat_ids))
    return 0


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description="Send Vegan Basket Telegram notifications.")
    parser.add_argument(
        "--failure",
        action="store_true",
        help="Send a short pipeline failure alert instead of the daily digest.",
    )
    parser.add_argument(
        "--exit-code",
        type=int,
        default=1,
        help="Exit code to include in a failure alert (default: 1).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the message instead of sending it to Telegram.",
    )
    args = parser.parse_args(argv)

    try:
        if args.failure:
            return send_failure_alert(args.exit_code, dry_run=args.dry_run)
        return send_success_digest(dry_run=args.dry_run)
    except Exception as exc:
        logger.error("Telegram notification failed (non-fatal): %s", exc)
        return 0


if __name__ == "__main__":
    sys.exit(main())
