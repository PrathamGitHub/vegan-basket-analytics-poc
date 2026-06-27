-- Grain: one row per (transaction_date, transaction_key, product_name)
--
-- This is the single source of truth for the BI dashboard.  All four global
-- filters — temporal, product, vendor, customer — are present as columns so
-- every Rill chart on the canvas can be filtered uniformly.
--
-- Payment allocation:  a vendor/customer payment is recorded at the
-- transaction level (not per product).  Here we distribute it proportionally
-- to each item's share of the transaction amount so that:
--   • sum(allocated_payment) over all items = payment_amount  (no double-count)
--   • product-level payment estimates remain meaningful for filtering
-- Fallback: equal split across items when all items are missing_rate.

with items as (
    select * from {{ ref('transaction_items_enriched') }}
),

payments as (
    select * from {{ ref('transaction_payment') }}
),

-- per-transaction totals needed for proportional allocation
item_totals as (
    select
        transaction_key,
        count(*)                             as item_count,
        sum(coalesce(transaction_amount, 0)) as total_tx_amount
    from items
    group by transaction_key
),

allocated as (
    select
        i.transaction_date                            as date,
        date_trunc('week', i.transaction_date)::date  as week_start,
        date_trunc('month', i.transaction_date)::date as month_start,
        i.transaction_key,
        i.transaction_type,
        i.vendor_name,
        i.customer_name,
        i.product_name,
        i.quantity_kg,
        i.applicable_rate,
        coalesce(i.transaction_amount, 0)             as transaction_amount,
        i.rate_lookup_status,
        p.payment_mode,
        coalesce(p.payment_amount, 0)                 as total_payment,
        case
            when it.total_tx_amount > 0
                then round(
                    coalesce(p.payment_amount, 0)
                    * coalesce(i.transaction_amount, 0)
                    / it.total_tx_amount,
                    2
                )
            else round(coalesce(p.payment_amount, 0) / it.item_count, 2)
        end                                           as allocated_payment
    from items i
    left join payments     p  on i.transaction_key = p.transaction_key
    left join item_totals  it on i.transaction_key = it.transaction_key
)

select
    date,
    week_start,
    month_start,
    transaction_key,
    transaction_type,
    vendor_name,
    customer_name,
    product_name,
    quantity_kg,
    applicable_rate,
    transaction_amount,
    rate_lookup_status,
    payment_mode,
    allocated_payment
from allocated
