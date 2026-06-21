with items as (
    select * from {{ ref('transaction_items') }}
),

vendor_rate_rows as (
    select
        items.transaction_key,
        items.product_name,
        rates.effective_from,
        {{ product_rate_from_wide_row('items.product_name') }} as applicable_rate,
        row_number() over (
            partition by items.transaction_key, items.product_name
            order by rates.effective_from desc
        ) as rate_rank
    from items
    inner join {{ ref('stg_vendor_rates') }} as rates
        on items.vendor_name = rates.vendor_name
        and rates.effective_from <= items.transaction_date
    where items.transaction_type = 'Purchase'
),

customer_rate_rows as (
    select
        items.transaction_key,
        items.product_name,
        rates.effective_from,
        {{ product_rate_from_wide_row('items.product_name') }} as applicable_rate,
        row_number() over (
            partition by items.transaction_key, items.product_name
            order by rates.effective_from desc
        ) as rate_rank
    from items
    inner join {{ ref('stg_customer_rates') }} as rates
        on items.customer_name = rates.customer_name
        and rates.effective_from <= items.transaction_date
    where items.transaction_type = 'Sale'
),

applicable_rates as (
    select
        transaction_key,
        product_name,
        applicable_rate
    from vendor_rate_rows
    where rate_rank = 1

    union all

    select
        transaction_key,
        product_name,
        applicable_rate
    from customer_rate_rows
    where rate_rank = 1
),

enriched as (
    select
        items.transaction_key,
        items.transaction_date,
        items.transaction_type,
        items.vendor_name,
        items.customer_name,
        items.product_name,
        items.quantity_kg,
        rates.applicable_rate,
        items.payment_amount
    from items
    left join applicable_rates as rates
        on items.transaction_key = rates.transaction_key
        and items.product_name = rates.product_name
)

select
    transaction_key,
    transaction_date,
    transaction_type,
    vendor_name,
    customer_name,
    product_name,
    quantity_kg,
    applicable_rate,
    case
        when applicable_rate is not null
        then round(quantity_kg * applicable_rate, 2)
    end as transaction_amount,
    payment_amount,
    case
        when applicable_rate is not null then 'matched'
        else 'missing_rate'
    end as rate_lookup_status
from enriched
