-- Fails when any product line has zero or negative quantity.
select *
from {{ ref('transaction_items') }}
where quantity_kg <= 0
