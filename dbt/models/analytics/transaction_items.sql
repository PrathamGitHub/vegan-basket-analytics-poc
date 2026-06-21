{% set product_columns = [
    ('Mushroom Bulk', 'mushroom_bulk_qty_kg'),
    ('Mushroom Pannet', 'mushroom_pannet_qty_kg'),
    ('Mushroom B Grade', 'mushroom_b_grade_qty_kg'),
    ('Baby Corn', 'baby_corn_qty_kg'),
    ('Lahsun', 'lahsun_qty_kg'),
] %}

with staged as (
    select * from {{ ref('stg_transaction_log') }}
)

{% for product_name, qty_col in product_columns %}
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
    transaction_type,
    vendor_name,
    customer_name,
    '{{ product_name }}' as product_name,
    {{ qty_col }} as quantity_kg,
    payment_rs as payment_amount,
    payment_mode,
    remarks
from staged
where {{ qty_col }} > 0
{% if not loop.last %}
union all
{% endif %}
{% endfor %}
