-- Acceptance: for transaction_date 2026-06-10, rates on 2026-06-01 (120),
-- 2026-06-05 (130), and 2026-06-15 (140) must resolve to 130.
with fixture_rates as (
    select date '2026-06-01' as effective_from, 120.0::decimal(10, 2) as rate_rs
    union all
    select date '2026-06-05', 130.0::decimal(10, 2)
    union all
    select date '2026-06-15', 140.0::decimal(10, 2)
),

selected_rate as (
    select rate_rs
    from fixture_rates
    where effective_from <= date '2026-06-10'
    order by effective_from desc
    limit 1
)

select *
from selected_rate
where rate_rs != 130.0
