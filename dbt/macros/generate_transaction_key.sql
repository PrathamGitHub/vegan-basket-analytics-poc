{% macro generate_transaction_key(
    timestamp_col,
    transaction_type_col,
    vendor_name_col,
    customer_name_col,
    payment_amount_col
) %}
md5(
    coalesce(cast({{ timestamp_col }} as varchar), '')
    || '|' || coalesce({{ transaction_type_col }}, '')
    || '|' || coalesce({{ vendor_name_col }}, '')
    || '|' || coalesce({{ customer_name_col }}, '')
    || '|' || coalesce(cast({{ payment_amount_col }} as varchar), '')
)
{% endmacro %}
