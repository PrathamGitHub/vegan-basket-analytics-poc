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

## Multiple recipients (2–3 people)

Two delivery modes are supported and can coexist. Both read from `.env` — the
digest module merges and deduplicates them automatically.

### Option A — Group chat (recommended)

One chat ID on the server; add/remove people from the Telegram app with no
server changes ever.

**Client steps (in the Telegram app):**

1. Create a new **private group** (any name, e.g. "Vegan Basket Ops").
2. Add the 2–3 people who should receive the digest.
3. Add your bot as a member (search by its username).
4. The bot must receive at least one message in the group before it can post.
   Send `/start` or any text to activate it.

**Get the group chat ID:**

1. Send any message to the group.
2. On the server, run:
   ```bash
   curl -s "https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates" | python3 -m json.tool
   ```
3. Find the group's chat object — group IDs are **negative** numbers like `-1001234567890`.

**Server `.env`:**

```bash
TELEGRAM_BOT_TOKEN=123456789:AAHxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TELEGRAM_CHAT_ID=-1001234567890    # group's negative ID
```

To add a recipient later: add them to the group in Telegram. No `.env` change needed.

---

### Option B — Individual DMs (comma-separated IDs)

Each person gets their own copy of the message, delivered independently. A
failure to reach one recipient does not block the others.

**Client steps for each person:**

1. They open the bot link and tap **Start**.
2. They get their own chat ID via **@userinfobot** (search in Telegram → `/start`).
3. They share that ID with you.

**Server `.env`:**

```bash
TELEGRAM_BOT_TOKEN=123456789:AAHxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TELEGRAM_CHAT_IDS=111111111,222222222,333333333
```

To add a recipient: edit `.env`, add their ID to `TELEGRAM_CHAT_IDS`
(comma-separated, no spaces). The systemd timer picks up `.env` changes on the
next run — no restart needed.

---

### Combining both

Both variables can be set at the same time. The digest module reads
`TELEGRAM_CHAT_IDS` first, then `TELEGRAM_CHAT_ID`, and deduplicates the
merged list. Useful when a group chat and one personal DM both need the digest.

```bash
TELEGRAM_CHAT_ID=-1001234567890        # group
TELEGRAM_CHAT_IDS=111111111,222222222  # two individual DMs as well
```

---

## Part 2 — Server setup

All steps run on the machine that executes the daily timer (same host as the repo).

### 1. Add secrets to `.env`

In the repo root (`~/work/projects/vegan-basket-analytics-poc/.env`):

```bash
# Telegram daily digest
TELEGRAM_BOT_TOKEN=123456789:AAHxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Single recipient or group chat (see "Multiple recipients" above for group ID)
TELEGRAM_CHAT_ID=987654321

# Optional: comma-separated individual DM IDs (merged with TELEGRAM_CHAT_ID)
# TELEGRAM_CHAT_IDS=111111111,222222222

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
| `Telegram digest skipped: set TELEGRAM_BOT_TOKEN...` | Add token and at least one of `TELEGRAM_CHAT_ID` / `TELEGRAM_CHAT_IDS` to `.env` |
| HTTP 403 / "bot can't initiate conversation" | Each DM recipient must tap **Start** on the bot first; for groups the bot must receive one message |
| HTTP 400 "chat not found" | Wrong chat ID — re-check personal IDs with @userinfobot; re-check group ID with `getUpdates` |
| HTTP 400 "can't parse entities" | Rare MarkdownV2 escape issue — run `--dry-run` and file an issue with the output |
| One recipient gets it, another doesn't | Each ID is sent independently; check the log line `Failed to send to chat <id>: …` |
| Digest never arrives but ingest succeeds | Check log for `Telegram digest could not be sent`; verify outbound HTTPS from the server |
| Failure alert but no success digest | Ingest exited non-zero before the digest step; fix pipeline/dbt first |

---

## Architecture notes

| Decision | Choice |
|----------|--------|
| Integration point | `python -m src.telegram_digest` at end of `scripts/run_daily.sh` |
| Cadence | Every timer run (including revision-guard skips) |
| Failure vs success | Separate short failure alert; full metrics digest on success |
| Multi-recipient | Group chat (`TELEGRAM_CHAT_ID`) and/or individual DMs (`TELEGRAM_CHAT_IDS`); merged + deduplicated |
| Per-recipient failure | Send continues to remaining recipients; failures logged, non-fatal |
| Overall metrics | Latest AR/AP + MTD + Indian FYTD (Apr–Mar) |
| Format | MarkdownV2, emoji section headers, raw numbers |
| Failure mode | Telegram errors are logged and ignored (exit 0) |

Implementation: `src/telegram_digest.py`  
Pipeline status file: `data/last_ingest_run.json`
