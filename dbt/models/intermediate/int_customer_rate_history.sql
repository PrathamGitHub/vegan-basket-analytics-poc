{% set product_columns = [
    ('Mushroom Bulk', 'mushroom_bulk_rate_rs'),
    ('Mushroom Pannet', 'mushroom_pannet_rate_rs'),
    ('Mushroom B Grade', 'mushroom_b_grade_rate_rs'),
    ('Baby Corn', 'baby_corn_rate_rs'),
    ('Lahsun', 'lahsun_rate_rs'),
] %}

with staged as (
    select * from {{ ref('stg_customer_rates') }}
)

{% for product_name, rate_col in product_columns %}
select
    customer_name,
    '{{ product_name }}' as product_name,
    effective_from,
    {{ rate_col }} as rate_rs,
    remarks
from staged
{% if not loop.last %}
union all
{% endif %}
{% endfor %}
