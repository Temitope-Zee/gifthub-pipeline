# Cleaning Decisions Log: Bronze to Silver

**Model:** `dbt/models/silver/silver_sales.sql`
**Source:** `bronze.online_retail` (Online Retail II, UCI Machine Learning Repository)
**Evidence files:** `docs/06_bronze_profile.txt`, `docs/07_pre_silver_checks.txt`, `docs/08_silver_reconciliation.txt`

## Guiding principle

Silver **labels** data instead of deleting it. The only rows removed are exact duplicates. Every other issue is handled with a flag or a clearly marked replacement value, so reports can include or exclude lines by changing a filter, and no information is lost if a rule changes later.

## Summary

| Measure | Bronze | Silver |
|---|---|---|
| Rows | 1,067,371 | 1,033,036 |
| Duplicate rows | 34,335 | 0 |
| Cancelled lines | 19,494 | 19,104 |
| Unknown customers | 243,007 | 235,151 |
| Missing descriptions | 4,382 | 4,275 |
| Column types | all text | integer, numeric, timestamp, date, boolean, text |
| Row reconciliation | | PASS |
| dbt tests | | 8 of 8 passed |

## Decisions

### Rule 1: Remove exact duplicate rows
- **Evidence:** 34,335 rows are identical to another row in all 8 source columns (3.2%). 22,202 duplicate groups appear in both Excel sheets, which indicates the two yearly sheets overlap.
- **Decision:** Keep one copy of each identical row.
- **Reason:** Most duplicates come from the export overlap, not from real repeat purchases. Keeping them would overstate revenue.
- **Result:** 1,033,036 rows. Reconciliation check 1: PASS.

### Rule 2: Keep guest purchases
- **Evidence:** 243,007 lines (22.8%) have no Customer ID.
- **Decision:** Keep these lines and set `customer_id = 'UNKNOWN'`.
- **Reason:** These are real sales. Deleting them would remove almost a quarter of the business's transactions.
- **Result:** 235,151 lines labelled UNKNOWN (7,856 fewer, because those were duplicates).
- **Note for Gold:** Customer-level analysis (top 10% of customers) must exclude UNKNOWN and say so.

### Rule 3: Flag cancellations
- **Evidence:** 19,494 lines have an invoice starting with C.
- **Decision:** `is_cancelled = true`. Do not delete.
- **Reason:** Needed to report cancellation rate and revenue lost.
- **Result:** 19,104 cancelled lines, worth -£1,462,050.61.

### Rule 4: Flag adjustments
- **Evidence:** 22,950 lines have a negative quantity, 3,456 more than the cancellations. 6,202 lines have a zero price and 5 have a negative price.
- **Decision:** `is_adjustment = true` for lines that are not cancellations but have a negative quantity or a zero or negative price.
- **Reason:** These are stock corrections and write-offs, not sales.
- **Result:** 6,019 adjustment lines.

### Rule 5: Flag non-product codes
- **Evidence:** Stock codes that are fees, adjustments, vouchers or test items (Bronze profile query 9; pre-Silver query B and the full follow-up list).
- **Decision:** Keep an explicit reference list in `dbt/seeds/non_product_codes.csv` and set `is_product = false` for those codes.
- **Reason:** A pattern such as "letters only" would wrongly exclude real products (party bags `DCGSSGIRL`, `DCGSSBOY`, `DCGSLGIRL` and cushion pads `PADS`). An explicit list is accurate, documented and easy for the business to update.
- **Result:**

| Type | Lines | Value |
|---|---|---|
| fee | 3,941 | £168,474.33 |
| adjustment | 1,742 | -£242,229.81 |
| voucher | 100 | £1,686.61 |
| test | 17 | £203.50 |

- **Vouchers:** excluded from product sales because selling a gift voucher is not selling goods. The revenue is earned when the voucher is used.
- **Stock codes are upper-cased before matching,** so `m` and `M` are treated as the same code.

### Rule 6: Replace missing descriptions
- **Evidence:** 4,382 descriptions missing. 0 descriptions consisting only of spaces.
- **Decision:** Replace missing or blank descriptions with `UNKNOWN PRODUCT`.
- **Reason:** Dashboard labels must never be empty.
- **Result:** 4,275 lines labelled UNKNOWN PRODUCT.

### Rule 7: Standardise country names
- **Evidence:** 43 country names, including abbreviations and non-English names (pre-Silver query C).
- **Decision:** Map using `dbt/seeds/country_mapping.csv`:

| Raw | Clean |
|---|---|
| EIRE | Ireland |
| RSA | South Africa |
| USA | United States |
| Unspecified | Unknown |

- **Result:** 0 unmapped values remain (reconciliation check 4).

### Rule 8: Convert data types
- **Decision:** quantity to integer; price to numeric; invoice date to timestamp plus a separate date column; text trimmed and upper-cased where used for matching.
- **Reason:** Text cannot be summed or sorted correctly. Money uses `numeric`, which is exact, instead of `float`, which can introduce rounding errors.
- **Result:** Reconciliation check 5 shows the new types.

### Rule 9: Calculate line revenue
- **Decision:** `line_revenue = quantity x unit_price`.
- **Result:**

| Measure | Value |
|---|---|
| All lines added together | £18,855,533.70 |
| Valid sales only (`is_valid_sale = true`) | £19,643,861.64 |
| Cancellations | -£1,462,050.61 |
| Other non-valid lines | £673,722.67 |

- **Finding:** Adding up every line understates product sales by £788,327.94 (about 4%), because refunds, fees, vouchers and adjustments are mixed in. This is why reports disagreed before the pipeline existed.

## Assumptions

1. Rows identical in all 8 source columns are duplicates, not repeat purchases.
2. Stock code `C3` is a carriage charge like `C2`. It has no description in the data.

## Known limitations

1. **Description gap:** our 4,382 missing descriptions differ from the 4,474 reported by the OpenML copy of this dataset. Blank-space descriptions were ruled out (0 found). Our figure comes directly from the original UCI file and is used.
2. **Regions, not countries:** `European Community`, `Channel Islands` and `West Indies` are kept as they are, because the specific country cannot be determined.

## Open questions for the business

1. Is stock code `DCGS0069` ("ebay", 6 lines) a product or a marketplace marker? Currently treated as a product.
2. Should region names such as `European Community` be grouped as "Other" in reporting?
3. For the dashboard, should "net revenue" be valid sales minus cancellations of products only, or minus all cancellations? (To be decided in Phase 4.)
