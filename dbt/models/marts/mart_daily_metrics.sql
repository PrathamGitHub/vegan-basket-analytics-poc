with inventory_lines as (
    select * from {{ ref('transaction_items_enriched') }}
),

daily_inventory as (
    select
        transaction_date as date,
        sum(
            case when transaction_type = 'Purchase' then quantity_kg else 0 end
        ) as purchase_qty,
        sum(
            case
                when transaction_type = 'Purchase' and rate_lookup_status = 'matched'
                then transaction_amount
                else 0
            end
        ) as purchase_amount,
        sum(
            case when transaction_type = 'Sale' then quantity_kg else 0 end
        ) as sales_qty,
        sum(
            case
                when transaction_type = 'Sale' and rate_lookup_status = 'matched'
                then transaction_amount
                else 0
            end
        ) as sales_amount
    from inventory_lines
    group by 1
),

daily_payments as (
    select
        transaction_date as date,
        sum(
            case when transaction_type = 'Purchase' then payment_rs else 0 end
        ) as payments_paid,
        sum(
            case when transaction_type = 'Sale' then payment_rs else 0 end
        ) as payments_received
    from {{ ref('stg_transaction_log') }}
    where payment_rs != 0
    group by 1
),

activity_dates as (
    select date from daily_inventory
    union
    select date from daily_payments
),

date_bounds as (
    select
        min(date) as min_date,
        max(date) as max_date
    from activity_dates
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
        date_spine.date,
        coalesce(daily_inventory.purchase_qty, 0) as purchase_qty,
        coalesce(daily_inventory.purchase_amount, 0) as purchase_amount,
        coalesce(daily_inventory.sales_qty, 0) as sales_qty,
        coalesce(daily_inventory.sales_amount, 0) as sales_amount,
        coalesce(daily_payments.payments_paid, 0) as payments_paid,
        coalesce(daily_payments.payments_received, 0) as payments_received
    from date_spine
    left join daily_inventory
        on date_spine.date = daily_inventory.date
    left join daily_payments
        on date_spine.date = daily_payments.date
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
