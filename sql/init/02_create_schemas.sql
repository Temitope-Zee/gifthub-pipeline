-- Runs automatically the first time the PostgreSQL container starts,
-- inside the warehouse database (POSTGRES_DB in .env).
-- Creates the three Medallion layers.

CREATE SCHEMA IF NOT EXISTS bronze;  -- raw data, exactly as received
CREATE SCHEMA IF NOT EXISTS silver;  -- cleaned and standardised data
CREATE SCHEMA IF NOT EXISTS gold;    -- star schema for reporting

COMMENT ON SCHEMA bronze IS 'Raw data loaded as-is from source files';
COMMENT ON SCHEMA silver IS 'Cleaned, de-duplicated, correctly typed data';
COMMENT ON SCHEMA gold   IS 'Fact and dimension tables for the dashboard';
