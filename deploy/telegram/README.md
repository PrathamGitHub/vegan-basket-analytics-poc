# Telegram Daily Digest — Setup Guide

Sends a **private Markdown digest** to your Telegram account after every nightly
ingestion run (`scripts/run_daily.sh` → pipeline → dbt → digest).

On failure, a short **🚨 alert** is sent instead (via an `ERR` trap in the shell
wrapper). Telegram errors never fail the ingest job.

---

## What you get

Example success message (values are illustrative):

```
📊 Vegan Basket Daily Digest
2026-06-27 IST

📈 Today (2026-06-27)
Sales: ₹42,500 (18 txn) · Qty 120.5 kg
Purchases: ₹31,200 · Qty 95.0 kg
Collected: ₹38,000 · Paid: ₹28,000

💼 Overall (2026-06-27)
AR: ₹1,24,000 · AP: ₹89,500
MTD sales: ₹8,50,000 · MTD purchases: ₹6,20,000
FYTD sales: ₹42,00,000 · FYTD purchases: ₹31,00,000

⚙️ Pipeline
Ingest: skipped (no new sheet rows)
dbt: OK
Runtime: 1m 42s
```

| Section | Source |
|---------|--------|
| **Today** | `marts.mart_daily_metrics` + transaction count from `marts.mart_transactions` for the report date (IST) |
| **Overall** | Latest cumulative AR/AP; MTD and FYTD (Apr 1 – Mar 31) sales & purchases |
| **Pipeline** | `data/last_ingest_run.json` (written by the pipeline) + wall-clock runtime |

---

## Part 1 — Client setup (Telegram app)

Do this once on your phone or desktop Telegram client.

### 1. Create a bot

1. Open Telegram and search for **@BotFather**.
2. Send `/newbot`.
3. Choose a display name (e.g. `Vegan Basket Analytics`).
4. Choose a username ending in `bot` (e.g. `vegan_basket_analytics_bot`).
5. BotFather replies with an **HTTP API token** like:
   ```
   123456789:AAHxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   ```
   Copy it — this is `TELEGRAM_BOT_TOKEN`. **Keep it secret.**

### 2. Start a chat with your bot

1. Open the bot link BotFather gives you (or search the username).
2. Tap **Start** (or send `/start`).

> The bot cannot message you until you have sent at least one message to it.

### 3. Get your chat ID

**Option A — @userinfobot (easiest)**

1. Search **@userinfobot** in Telegram.
2. Send `/start`.
3. It replies with your numeric **Id** (e.g. `987654321`). That is `TELEGRAM_CHAT_ID`.

**Option B — Bot API**

1. Send any message to your new bot.
2. On the server (after the token is in `.env`), run:
   ```bash
   curl -s "https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates" | python3 -m json.tool
   ```
3. Find `"chat":{"id":987654321,...}` in the response.

Use a **positive** integer for a private DM. (Group chats use negative IDs.)

---

## Part 2 — Server setup

All steps run on the machine that executes the daily timer (same host as the repo).

### 1. Add secrets to `.env`

In the repo root (`~/work/projects/vegan-basket-analytics-poc/.env`):

```bash
# Telegram daily digest (private bot → your DM)
TELEGRAM_BOT_TOKEN=123456789:AAHxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TELEGRAM_CHAT_ID=987654321

# Optional — set false to disable without removing tokens
TELEGRAM_DIGEST_ENABLED=true
```

Rules for systemd:

- Use **bare values** (no quotes). systemd strips quotes from `.env` values.
- Never commit `.env` to git.

The systemd unit already loads this file via `EnvironmentFile=` — no unit changes needed after editing `.env`.

### 2. Test without waiting for the timer

From the repo root with the virtualenv active:

```bash
source .venv/bin/activate

# Preview the message (no Telegram API call)
python -m src.telegram_digest --dry-run

# Send a real test digest
python -m src.telegram_digest

# Preview / send a failure alert
python -m src.telegram_digest --failure --exit-code=1 --dry-run
python -m src.telegram_digest --failure --exit-code=1
```

You should receive the message in your Telegram DM within a few seconds.

### 3. Test via the full daily script

```bash
./scripts/run_daily.sh
```

Or trigger the systemd service:

```bash
systemctl --user start vegan-basket-ingest.service
```

Check logs if something fails:

```bash
journalctl --user -u vegan-basket-ingest -n 80
tail -50 data/logs/ingest-$(date +%Y-%m-%d).log
```

### 4. Disable temporarily

Set in `.env`:

```bash
TELEGRAM_DIGEST_ENABLED=false
```

The nightly job continues; digest calls become no-ops with a log line.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Telegram digest skipped: set TELEGRAM_BOT_TOKEN...` | Add both token and chat ID to `.env`; restart is not required for the next manual run |
| HTTP 403 / "bot can't initiate conversation" | Open the bot in Telegram and tap **Start** first |
| HTTP 400 "chat not found" | Wrong `TELEGRAM_CHAT_ID`; re-check with @userinfobot |
| HTTP 400 "can't parse entities" | Rare MarkdownV2 escape issue — file an issue with `--dry-run` output |
| Digest never arrives but ingest succeeds | Check log for `Telegram digest could not be sent`; verify outbound HTTPS from the server |
| Failure alert but no success digest | Ingest exited non-zero before the digest step; fix pipeline/dbt first |

---

## Architecture notes

| Decision | Choice |
|----------|--------|
| Integration point | `python -m src.telegram_digest` at end of `scripts/run_daily.sh` |
| Cadence | Every timer run (including revision-guard skips) |
| Failure vs success | Separate short failure alert; full metrics digest on success |
| Overall metrics | Latest AR/AP + MTD + Indian FYTD (Apr–Mar) |
| Format | MarkdownV2, emoji section headers, raw numbers |
| Failure mode | Telegram errors are logged and ignored (exit 0) |

Implementation: `src/telegram_digest.py`  
Pipeline status file: `data/last_ingest_run.json`
