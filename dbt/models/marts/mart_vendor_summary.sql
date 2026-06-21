with inventory_lines as (
    select *
    from {{ ref('transaction_items_enriched') }}
    where transaction_type = 'Purchase'
        and vendor_name is not null
),

vendor_purchases as (
    select
        vendor_name,
        sum(quantity_kg) as purchase_qty,
        sum(
            case
                when rate_lookup_status = 'matched' then transaction_amount
                else 0
            end
        ) as purchase_amount
    from inventory_lines
    group by 1
),

vendor_payments as (
    select
        vendor_name,
        sum(payment_rs) as payments_paid
    from {{ ref('stg_transaction_log') }}
    where transaction_type = 'Purchase'
        and payment_rs != 0
        and vendor_name is not null
    group by 1
),

vendors as (
    select vendor_name from vendor_purchases
    union
    select vendor_name from vendor_payments
)

select
    vendors.vendor_name,
    coalesce(vendor_purchases.purchase_qty, 0) as purchase_qty,
    coalesce(vendor_purchases.purchase_amount, 0) as purchase_amount,
    coalesce(vendor_purchases.purchase_amount, 0)
    - coalesce(vendor_payments.payments_paid, 0) as outstanding_payable
from vendors
left join vendor_purchases
    on vendors.vendor_name = vendor_purchases.vendor_name
left join vendor_payments
    on vendors.vendor_name = vendor_payments.vendor_name
