-- Grain: (date, vendor_name) — daily purchase activity per vendor with a
-- continuous date spine (zero-filled on inactive days) and a cumulative
-- outstanding_payable running balance.
--
-- Temporal filter in Rill (timeseries: date) and vendor filter both apply.
-- Source: mart_transactions keeps allocated payments consistent.

with vendor_daily as (
    select
        date,
        vendor_name,
        sum(quantity_kg)        as purchase_qty,
        sum(transaction_amount) as purchase_amount,
        sum(allocated_payment)  as payments_paid
    from {{ ref('mart_transactions') }}
    where transaction_type = 'Purchase'
      and vendor_name is not null
    group by date, vendor_name
),

vendors as (
    select distinct vendor_name from vendor_daily
),

date_bounds as (
    select min(date) as min_date, max(date) as max_date
    from vendor_daily
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

vendor_spine as (
    select ds.date, v.vendor_name
    from date_spine ds
    cross join vendors v
),

filled as (
    select
        vs.date,
        vs.vendor_name,
        coalesce(vd.purchase_qty,    0) as purchase_qty,
        coalesce(vd.purchase_amount, 0) as purchase_amount,
        coalesce(vd.payments_paid,   0) as payments_paid
    from vendor_spine vs
    left join vendor_daily vd
        on vs.date       = vd.date
        and vs.vendor_name = vd.vendor_name
)

select
    date,
    vendor_name,
    purchase_qty,
    purchase_amount,
    payments_paid,
    sum(purchase_amount - payments_paid) over (
        partition by vendor_name
        order by date
        rows between unbounded preceding and current row
    ) as outstanding_payable
from filled
