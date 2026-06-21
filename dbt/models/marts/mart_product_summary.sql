select
    product_name,
    sum(
        case when transaction_type = 'Purchase' then quantity_kg else 0 end
    ) as purchase_qty,
    sum(
        case when transaction_type = 'Sale' then quantity_kg else 0 end
    ) as sales_qty,
    sum(
        case
            when transaction_type = 'Purchase' and rate_lookup_status = 'matched'
            then transaction_amount
            else 0
        end
    ) as purchase_amount,
    sum(
        case
            when transaction_type = 'Sale' and rate_lookup_status = 'matched'
            then transaction_amount
            else 0
        end
    ) as sales_amount
from {{ ref('transaction_items_enriched') }}
group by 1
