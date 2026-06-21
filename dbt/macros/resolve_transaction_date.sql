{% macro resolve_transaction_date(timestamp_col, transaction_date_raw_col) %}
case
    when {{ transaction_date_raw_col }} is not null
     and {{ transaction_date_raw_col }} != current_date
    then {{ transaction_date_raw_col }}
    else cast({{ timestamp_col }} as date)
end
{% endmacro %}
