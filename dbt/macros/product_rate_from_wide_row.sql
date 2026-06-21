{% macro product_rate_from_wide_row(product_name_col) %}
case {{ product_name_col }}
    when 'Mushroom Bulk' then mushroom_bulk_rate_rs
    when 'Mushroom Pannet' then mushroom_pannet_rate_rs
    when 'Mushroom B Grade' then mushroom_b_grade_rate_rs
    when 'Baby Corn' then baby_corn_rate_rs
    when 'Lahsun' then lahsun_rate_rs
end
{% endmacro %}
