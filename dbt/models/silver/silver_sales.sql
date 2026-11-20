/*
  silver_sales: cleaned, typed and labelled sales lines.
  Source: bronze.online_retail (raw text, exactly as received).
  Grain:  one row per unique invoice line.

  Rules applied (see docs/cleaning_decisions.md for the evidence behind each):
    1. Remove exact duplicate rows
    2. Keep guest purchases, with customer_id = 'UNKNOWN'
    3. Flag cancellations (invoice starts with C)
    4. Flag adjustments (negative quantity or zero/negative price, not a cancellation)
    5. Flag non-product codes using the non_product_codes reference list
    6. Replace missing or blank descriptions with 'UNKNOWN PRODUCT'
    7. Standardise country names using the country_mapping reference list
    8. Convert text to proper data types
    9. Calculate line_revenue = quantity x unit_price
*/

with source as (

    select * from {{ source('bronze', 'online_retail') }}

),

-- Rule 1: number identical rows 1, 2, 3...; only row 1 is kept further down.
-- A unique ID for each line is built from the raw values at the same time.
deduplicated as (

    select
        *,
        row_number() over (
            partition by invoice, stockcode, description, quantity,
                         invoicedate, price, customer_id, country
            order by loaded_at
        ) as row_num,
        md5(concat_ws('|',
            coalesce(invoice, '<null>'),
            coalesce(stockcode, '<null>'),
            coalesce(description, '<null>'),
            coalesce(quantity, '<null>'),
            coalesce(invoicedate, '<null>'),
            coalesce(price, '<null>'),
            coalesce(customer_id, '<null>'),
            coalesce(country, '<null>')
        )) as sales_line_id
    from source

),

-- Rule 8: tidy text and convert to proper types.
-- Casting through NUMERIC first copes with values such as '12' and '12.0'.
typed as (

    select
        sales_line_id,
        upper(trim(invoice))                                  as invoice,
        upper(trim(stockcode))                                as stock_code,
        nullif(upper(trim(description)), '')                  as description_raw,
        cast(cast(quantity as numeric) as integer)            as quantity,
        cast(price as numeric)                                as unit_price,
        cast(invoicedate as timestamp)                        as invoiced_at,
        cast(cast(cast(nullif(trim(customer_id), '') as numeric) as bigint) as text) as customer_id_raw,
        trim(country)                                         as country_raw,
        source_sheet,
        loaded_at                                             as bronze_loaded_at
    from deduplicated
    where row_num = 1

),

-- Rules 5 and 7: look up the reference lists (dbt seeds).
labelled as (

    select
        t.*,
        coalesce(cm.country_clean, t.country_raw)            as country,
        np.code_type                                          as non_product_type
    from typed as t
    left join {{ ref('country_mapping') }} as cm
        on t.country_raw = cm.country_raw
    left join {{ ref('non_product_codes') }} as np
        on t.stock_code = np.stock_code

),

-- Rules 2, 3, 4, 5, 6 and 9: build the final columns and flags.
flagged as (

    select
        sales_line_id,
        invoice,
        stock_code,
        coalesce(description_raw, 'UNKNOWN PRODUCT')          as description,
        quantity,
        unit_price,
        quantity * unit_price                                 as line_revenue,
        invoiced_at,
        cast(invoiced_at as date)                             as invoice_date,
        coalesce(customer_id_raw, 'UNKNOWN')                  as customer_id,
        country,
        invoice like 'C%'                                     as is_cancelled,
        non_product_type is null                              as is_product,
        non_product_type,
        source_sheet,
        bronze_loaded_at
    from labelled

)

select
    *,
    (not is_cancelled and (quantity < 0 or unit_price <= 0))  as is_adjustment,
    -- A normal sale: a real product, not cancelled, not an adjustment.
    (is_product and not is_cancelled
        and quantity > 0 and unit_price > 0)                  as is_valid_sale
from flagged
