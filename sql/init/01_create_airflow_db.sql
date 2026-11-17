-- Runs automatically the first time the PostgreSQL container starts.
-- Airflow needs its own database to store run history, users and task states.
-- Keeping it separate from the warehouse stops system tables mixing with business data.
CREATE DATABASE airflow;
