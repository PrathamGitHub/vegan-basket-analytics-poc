-- Company-level daily spine with cumulative outstanding balances.
-- Derived from mart_transactions so that allocated payments are consistent
-- with the product/vendor/customer breakdown marts.
--
-- outstanding_payable / outstanding_receivable are true cumulative running
-- balances from the first activity date.  Use arg_max(col, date) in Rill
-- to surface "balance as of period end" in KPI cards.

with daily_agg as (
    select
        date,
        sum(case when transaction_type = 'Purchase' then quantity_kg        else 0 end) as purchase_qty,
        sum(case when transaction_type = 'Purchase' then transaction_amount  else 0 end) as purchase_amount,
        sum(case when transaction_type = 'Sale'     then quantity_kg        else 0 end) as sales_qty,
        sum(case when transaction_type = 'Sale'     then transaction_amount  else 0 end) as sales_amount,
        sum(case when transaction_type = 'Purchase' then allocated_payment   else 0 end) as payments_paid,
        sum(case when transaction_type = 'Sale'     then allocated_payment   else 0 end) as payments_received
    from {{ ref('mart_transactions') }}
    group by date
),

date_bounds as (
    select min(date) as min_date, max(date) as max_date
    from daily_agg
),

date_spine as (
    select unnest(
        generate_series(
            (select min_date from date_bounds),
            (select max_date from date_bounds),
            interval 1 day
        )
    )::date as date
),

daily_combined as (
    select
        ds.date,
        coalesce(da.purchase_qty,      0) as purchase_qty,
        coalesce(da.purchase_amount,   0) as purchase_amount,
        coalesce(da.sales_qty,         0) as sales_qty,
        coalesce(da.sales_amount,      0) as sales_amount,
        coalesce(da.payments_paid,     0) as payments_paid,
        coalesce(da.payments_received, 0) as payments_received
    from date_spine ds
    left join daily_agg da on ds.date = da.date
)

select
    date,
    purchase_qty,
    purchase_amount,
    sales_qty,
    sales_amount,
    payments_paid,
    payments_received,
    sum(purchase_amount - payments_paid) over (
        order by date
        rows between unbounded preceding and current row
    ) as outstanding_payable,
    sum(sales_amount - payments_received) over (
        order by date
        rows between unbounded preceding and current row
    ) as outstanding_receivable
from daily_combined
