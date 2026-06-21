with inventory_lines as (
    select *
    from {{ ref('transaction_items_enriched') }}
    where transaction_type = 'Sale'
        and customer_name is not null
),

customer_sales as (
    select
        customer_name,
        sum(quantity_kg) as sales_qty,
        sum(
            case
                when rate_lookup_status = 'matched' then transaction_amount
                else 0
            end
        ) as sales_amount
    from inventory_lines
    group by 1
),

customer_payments as (
    select
        customer_name,
        sum(payment_rs) as payments_received
    from {{ ref('stg_transaction_log') }}
    where transaction_type = 'Sale'
        and payment_rs != 0
        and customer_name is not null
    group by 1
),

customers as (
    select customer_name from customer_sales
    union
    select customer_name from customer_payments
)

select
    customers.customer_name,
    coalesce(customer_sales.sales_qty, 0) as sales_qty,
    coalesce(customer_sales.sales_amount, 0) as sales_amount,
    coalesce(customer_sales.sales_amount, 0)
    - coalesce(customer_payments.payments_received, 0) as outstanding_receivable
from customers
left join customer_sales
    on customers.customer_name = customer_sales.customer_name
left join customer_payments
    on customers.customer_name = customer_payments.customer_name
