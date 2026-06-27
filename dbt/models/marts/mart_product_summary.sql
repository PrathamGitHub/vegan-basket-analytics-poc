-- Grain: (date, product_name) — daily purchase and sales activity per product.
-- Adding the date column enables temporal filtering in Rill (timeseries: date)
-- so the product breakdown responds correctly to date range filters.

select
    date,
    product_name,
    sum(case when transaction_type = 'Purchase' then quantity_kg        else 0 end) as purchase_qty,
    sum(case when transaction_type = 'Sale'     then quantity_kg        else 0 end) as sales_qty,
    sum(case when transaction_type = 'Purchase' then transaction_amount  else 0 end) as purchase_amount,
    sum(case when transaction_type = 'Sale'     then transaction_amount  else 0 end) as sales_amount
from {{ ref('mart_transactions') }}
group by date, product_name
