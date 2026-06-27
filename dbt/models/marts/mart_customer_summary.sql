-- Grain: (date, customer_name) — daily sales activity per customer with a
-- continuous date spine (zero-filled on inactive days) and a cumulative
-- outstanding_receivable running balance.
--
-- Temporal filter in Rill (timeseries: date) and customer filter both apply.
-- Source: mart_transactions keeps allocated payments consistent.

with customer_daily as (
    select
        date,
        customer_name,
        sum(quantity_kg)       as sales_qty,
        sum(transaction_amount) as sales_amount,
        sum(allocated_payment)  as payments_received
    from {{ ref('mart_transactions') }}
    where transaction_type = 'Sale'
      and customer_name is not null
    group by date, customer_name
),

customers as (
    select distinct customer_name from customer_daily
),

date_bounds as (
    select min(date) as min_date, max(date) as max_date
    from customer_daily
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

customer_spine as (
    select ds.date, c.customer_name
    from date_spine ds
    cross join customers c
),

filled as (
    select
        cs.date,
        cs.customer_name,
        coalesce(cd.sales_qty,          0) as sales_qty,
        coalesce(cd.sales_amount,       0) as sales_amount,
        coalesce(cd.payments_received,  0) as payments_received
    from customer_spine cs
    left join customer_daily cd
        on cs.date          = cd.date
        and cs.customer_name = cd.customer_name
)

select
    date,
    customer_name,
    sales_qty,
    sales_amount,
    payments_received,
    sum(sales_amount - payments_received) over (
        partition by customer_name
        order by date
        rows between unbounded preceding and current row
    ) as outstanding_receivable
from filled
