-- Phase 3, Step 7b: questions to answer BEFORE writing the Silver rules.
-- Run with:
--   docker exec -i gifthub_postgres psql -U gifthub -d gifthub_dw < sql/checks/pre_silver_checks.sql

\echo 'A. Descriptions that are blank spaces (not NULL, but empty after TRIM)'
SELECT COUNT(*) AS blank_descriptions
FROM bronze.online_retail
WHERE description IS NOT NULL AND TRIM(description) = '';

\echo 'B. Unusual stock codes: not 5 digits (+ up to 3 letters), and not letters only'
SELECT UPPER(TRIM(stockcode)) AS stock_code,
       MIN(description)       AS example_description,
       COUNT(*)               AS lines
FROM bronze.online_retail
WHERE UPPER(TRIM(stockcode)) !~ '^[0-9]{5}[A-Z]{0,3}$'
  AND UPPER(TRIM(stockcode)) !~ '^[A-Z ]+$'
GROUP BY 1
ORDER BY lines DESC
LIMIT 40;

\echo 'C. Every country name, alphabetically'
SELECT country, COUNT(*) AS lines
FROM bronze.online_retail
GROUP BY country
ORDER BY country;

\echo 'D. Duplicate groups that appear in BOTH Excel sheets'
SELECT COUNT(*) AS duplicate_groups_across_sheets
FROM (
    SELECT invoice, stockcode, description, quantity, invoicedate, price, customer_id, country
    FROM bronze.online_retail
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
    HAVING COUNT(DISTINCT source_sheet) > 1
) AS x;

\echo 'E. Lines with zero or negative price'
SELECT
    COUNT(*) FILTER (WHERE CAST(price AS NUMERIC) = 0) AS zero_price_lines,
    COUNT(*) FILTER (WHERE CAST(price AS NUMERIC) < 0) AS negative_price_lines
FROM bronze.online_retail;
