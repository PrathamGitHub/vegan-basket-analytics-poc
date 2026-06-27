# ── Stage 1: dependency installer ─────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt requirements-dev.txt ./
RUN pip install --no-cache-dir --prefix=/install \
    -r requirements.txt \
    -r requirements-dev.txt

# ── Stage 2: runtime ──────────────────────────────────────────────────────────
FROM python:3.12-slim

LABEL org.opencontainers.image.title="vegan-basket-pipeline"
LABEL org.opencontainers.image.description="Vegan Basket daily ingestion (dlt + dbt) with cron scheduler"

WORKDIR /app

# cron + process utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    cron \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Copy installed Python packages from builder
COPY --from=builder /install /usr/local

# Copy project source
COPY src/         ./src/
COPY dbt/         ./dbt/
COPY scripts/     ./scripts/

# Use the example profiles (relies on DUCKDB_PATH env var)
RUN cp dbt/profiles.yml.example dbt/profiles.yml

# Install dbt packages (downloads from dbt Hub; needs network at build time)
RUN dbt deps --project-dir dbt --profiles-dir dbt

# Create runtime directories (real data will be on mounted volumes)
RUN mkdir -p data/logs credentials

RUN chmod +x scripts/*.sh

# Register the cron job: 23:00 IST = 17:30 UTC
RUN printf '30 17 * * * root . /etc/environment; cd /app && /app/scripts/run_daily.sh\n' \
    > /etc/cron.d/vegan-basket \
    && chmod 0644 /etc/cron.d/vegan-basket

COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
