-- Phase 3, Step 14: prove Silver is correct by comparing it with Bronze.
-- Run with:
--   docker exec -i gifthub_postgres psql -U gifthub -d gifthub_dw < sql/checks/silver_reconciliation.sql

\echo '1. Row reconciliation: Silver should equal Bronze minus duplicates'
WITH b AS (SELECT COUNT(*) AS n FROM bronze.online_retail),
     d AS (SELECT COUNT(*) - COUNT(DISTINCT (invoice, stockcode, description, quantity,
                                            invoicedate, price, customer_id, country)) AS n
           FROM bronze.online_retail),
     s AS (SELECT COUNT(*) AS n FROM silver.silver_sales)
SELECT b.n            AS bronze_rows,
       d.n            AS duplicates_removed,
       b.n - d.n      AS expected_silver_rows,
       s.n            AS actual_silver_rows,
       CASE WHEN b.n - d.n = s.n THEN 'PASS' ELSE 'FAIL' END AS result
FROM b, d, s;

\echo '2. How many lines carry each label'
SELECT
    COUNT(*) FILTER (WHERE is_cancelled)               AS cancelled,
    COUNT(*) FILTER (WHERE is_adjustment)              AS adjustments,
    COUNT(*) FILTER (WHERE NOT is_product)             AS non_product,
    COUNT(*) FILTER (WHERE customer_id = 'UNKNOWN')    AS unknown_customer,
    COUNT(*) FILTER (WHERE description = 'UNKNOWN PRODUCT') AS unknown_description,
    COUNT(*) FILTER (WHERE is_valid_sale)              AS valid_sales
FROM silver.silver_sales;

\echo '3. Revenue: all lines compared with valid sales only (pounds)'
SELECT
    ROUND(SUM(line_revenue), 2)                                    AS all_lines_revenue,
    ROUND(SUM(line_revenue) FILTER (WHERE is_valid_sale), 2)       AS valid_sales_revenue,
    ROUND(SUM(line_revenue) FILTER (WHERE is_cancelled), 2)        AS cancelled_value
FROM silver.silver_sales;

\echo '4. Country fixes worked (should all be 0)'
SELECT COUNT(*) FILTER (WHERE country = 'EIRE')        AS eire_left,
       COUNT(*) FILTER (WHERE country = 'RSA')         AS rsa_left,
       COUNT(*) FILTER (WHERE country = 'USA')         AS usa_left,
       COUNT(*) FILTER (WHERE country = 'Unspecified') AS unspecified_left
FROM silver.silver_sales;

\echo '5. Data types in Silver (no more text-only columns)'
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'silver' AND table_name = 'silver_sales'
ORDER BY ordinal_position;

\echo '6. Non-product lines by type'
SELECT non_product_type, COUNT(*) AS lines, ROUND(SUM(line_revenue), 2) AS value
FROM silver.silver_sales
WHERE NOT is_product
GROUP BY non_product_type
ORDER BY lines DESC;
