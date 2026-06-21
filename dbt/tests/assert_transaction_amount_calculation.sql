-- Fails when a matched line has a null or mismatched transaction_amount.
select *
from {{ ref('transaction_items_enriched') }}
where rate_lookup_status = 'matched'
  and (
    applicable_rate is null
    or transaction_amount is null
    or transaction_amount != round(quantity_kg * applicable_rate, 2)
  )
