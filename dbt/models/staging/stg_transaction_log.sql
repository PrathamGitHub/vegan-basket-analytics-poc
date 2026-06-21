with source as (
    select * from {{ source('raw', 'transaction_log') }}
),

parsed as (
    select
        coalesce(
            try_strptime(timestamp, '%Y-%m-%d %H:%M:%S'),
            try_strptime(timestamp, '%m/%d/%Y %H:%M:%S'),
            try_strptime(timestamp, '%d/%m/%Y %H:%M:%S')
        )::timestamp as transaction_timestamp,

        case
            when nullif(trim(transaction_date), '') is null then null
            else coalesce(
                try_strptime(transaction_date, '%Y-%m-%d')::date,
                try_strptime(transaction_date, '%m/%d/%Y')::date,
                try_strptime(transaction_date, '%d/%m/%Y')::date
            )
        end as transaction_date_raw,

        case
            when lower(trim(transaction_type)) like 'purchase%' then 'Purchase'
            when lower(trim(transaction_type)) like 'sale%' then 'Sale'
            else trim(transaction_type)
        end as transaction_type,
        nullif(trim(vendor_name), '') as vendor_name,
        nullif(trim(customer_name), '') as customer_name,

        coalesce(
            try_cast(nullif(trim(payment_rs), '') as decimal(12, 2)),
            0
        ) as payment_rs,

        case
            when coalesce(
                try_cast(nullif(trim(payment_rs), '') as decimal(12, 2)),
                0
            ) != 0
            and nullif(trim(payment_mode), '') is null
            then 'Cash'
            else nullif(trim(payment_mode), '')
        end as payment_mode,

        coalesce(
            try_cast(nullif(trim(mushroom_bulk_qty_kg), '') as decimal(10, 3)),
            0
        ) as mushroom_bulk_qty_kg,
        coalesce(
            try_cast(nullif(trim(mushroom_pannet_qty_kg), '') as decimal(10, 3)),
            0
        ) as mushroom_pannet_qty_kg,
        coalesce(
            try_cast(nullif(trim(mushroom_b_grade_qty_kg), '') as decimal(10, 3)),
            0
        ) as mushroom_b_grade_qty_kg,
        coalesce(
            try_cast(nullif(trim(baby_corn_qty_kg), '') as decimal(10, 3)),
            0
        ) as baby_corn_qty_kg,
        coalesce(
            try_cast(nullif(trim(lahsun_qty_kg), '') as decimal(10, 3)),
            0
        ) as lahsun_qty_kg,

        nullif(trim(remarks), '') as remarks
    from source
)

select
    transaction_timestamp,
    transaction_date_raw,
    {{ resolve_transaction_date('transaction_timestamp', 'transaction_date_raw') }}
        as transaction_date,
    transaction_type,
    vendor_name,
    customer_name,
    payment_rs,
    payment_mode,
    mushroom_bulk_qty_kg,
    mushroom_pannet_qty_kg,
    mushroom_b_grade_qty_kg,
    baby_corn_qty_kg,
    lahsun_qty_kg,
    mushroom_bulk_qty_kg
    + mushroom_pannet_qty_kg
    + mushroom_b_grade_qty_kg
    + baby_corn_qty_kg
    + lahsun_qty_kg as total_qty_kg,
    remarks
from parsed
