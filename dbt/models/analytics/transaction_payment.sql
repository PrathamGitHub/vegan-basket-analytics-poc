with staged as (
    select * from {{ ref('stg_transaction_log') }}
)

select
    {{ generate_transaction_key(
        'transaction_timestamp',
        'transaction_type',
        'vendor_name',
        'customer_name',
        'payment_rs'
    ) }} as transaction_key,
    transaction_timestamp,
    transaction_date,
    case 
    when transaction_type = 'Purchase' then 'vendor_payment'
    when transaction_type = 'Sale' then 'customer_collection'
    else null
    end as payment_type,
    vendor_name,
    customer_name,
    payment_rs as payment_amount,
    payment_mode,
    remarks
from staged
where payment_rs != 0