with source as (
    select * from {{ source('raw', 'vendor_rates') }}
),

parsed as (
    select
        coalesce(
            try_strptime(nullif(trim(effective_from), ''), '%Y-%m-%d')::date,
            try_strptime(nullif(trim(effective_from), ''), '%m/%d/%Y')::date,
            try_strptime(nullif(trim(effective_from), ''), '%d/%m/%Y')::date
        ) as effective_from,
        nullif(trim(vendor_name), '') as vendor_name,
        try_cast(nullif(trim(mushroom_bulk_rate_rs), '') as decimal(10, 2))
            as mushroom_bulk_rate_rs,
        try_cast(nullif(trim(mushroom_pannet_rate_rs), '') as decimal(10, 2))
            as mushroom_pannet_rate_rs,
        try_cast(nullif(trim(mushroom_b_grade_rate_rs), '') as decimal(10, 2))
            as mushroom_b_grade_rate_rs,
        try_cast(nullif(trim(baby_corn_rate_rs), '') as decimal(10, 2))
            as baby_corn_rate_rs,
        try_cast(nullif(trim(lahsun_rate_rs), '') as decimal(10, 2))
            as lahsun_rate_rs,
        nullif(trim(remarks), '') as remarks
    from source
)

select *
from parsed
where effective_from is not null
  and vendor_name is not null
