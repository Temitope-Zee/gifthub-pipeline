-- Phase 2: profile the Bronze table.
-- These queries show what the raw data looks like, so we can plan the
-- cleaning rules for Silver (Phase 3). They change nothing.
--
-- Run all of them with:
--   docker exec -i gifthub_postgres psql -U gifthub -d gifthub_dw < sql/checks/bronze_profile.sql

\echo '1. Total rows and rows per sheet'
SELECT source_sheet, COUNT(*) AS row_count
FROM bronze.online_retail
GROUP BY source_sheet
ORDER BY source_sheet;

\echo '2. When was this batch loaded?'
SELECT DISTINCT loaded_at, source_file
FROM bronze.online_retail;

\echo '3. Missing values per column'
SELECT
    COUNT(*) FILTER (WHERE invoice     IS NULL) AS missing_invoice,
    COUNT(*) FILTER (WHERE stockcode   IS NULL) AS missing_stockcode,
    COUNT(*) FILTER (WHERE description IS NULL) AS missing_description,
    COUNT(*) FILTER (WHERE quantity    IS NULL) AS missing_quantity,
    COUNT(*) FILTER (WHERE invoicedate IS NULL) AS missing_invoicedate,
    COUNT(*) FILTER (WHERE price       IS NULL) AS missing_price,
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS missing_customer_id,
    COUNT(*) FILTER (WHERE country     IS NULL) AS missing_country
FROM bronze.online_retail;

\echo '4. Cancelled invoices (invoice starts with C)'
SELECT COUNT(*) AS cancelled_lines
FROM bronze.online_retail
WHERE invoice LIKE 'C%';

\echo '5. Lines with a negative quantity'
SELECT COUNT(*) AS negative_quantity_lines
FROM bronze.online_retail
WHERE quantity LIKE '-%';

\echo '6. Exact duplicate rows (same values in every source column)'
SELECT COUNT(*) - COUNT(DISTINCT (invoice, stockcode, description, quantity,
                                  invoicedate, price, customer_id, country))
       AS duplicate_rows
FROM bronze.online_retail;

\echo '7. Date range (dates are text in Bronze; ISO format sorts correctly)'
SELECT MIN(invoicedate) AS first_date, MAX(invoicedate) AS last_date
FROM bronze.online_retail;

\echo '8. Top 10 countries by number of lines'
SELECT country, COUNT(*) AS lines
FROM bronze.online_retail
GROUP BY country
ORDER BY lines DESC
LIMIT 10;

\echo '9. Stock codes that are not ordinary products (letters only)'
SELECT stockcode, MIN(description) AS example_description, COUNT(*) AS lines
FROM bronze.online_retail
WHERE stockcode ~ '^[A-Za-z ]+$'
GROUP BY stockcode
ORDER BY lines DESC
LIMIT 15;

\echo '10. Example of how Customer ID was stored'
SELECT customer_id
FROM bronze.online_retail
WHERE customer_id IS NOT NULL
LIMIT 5;
