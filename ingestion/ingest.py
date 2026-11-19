"""
Phase 2: Ingestion (Bronze layer)

Reads every sheet of the Online Retail II Excel file and loads the rows,
unchanged, into bronze.online_retail in the warehouse.

Run from the project root (with the virtual environment active):
    python ingestion/ingest.py

Design rules for Bronze:
  1. Keep the data exactly as received: every column is stored as TEXT.
     Fixing types and errors is Silver's job (Phase 3).
  2. Add audit columns so we always know where a row came from and when.
  3. Idempotent: running the script twice gives the same result, not double the rows.
  4. All-or-nothing: if the load fails halfway, the previous data is kept.
"""
import io
import logging
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

# ---------------------------------------------------------------------------
# 1. Settings
# ---------------------------------------------------------------------------
PROJECT_ROOT = Path(__file__).resolve().parent.parent
SOURCE_FILE = PROJECT_ROOT / "data" / "raw" / "online_retail_II.xlsx"
TARGET_TABLE = "bronze.online_retail"
EXPECTED_ROWS = 1_067_371  # total stated on the UCI dataset page

# The order of these columns must match the CREATE TABLE and COPY statements.
SOURCE_COLUMNS = [
    "invoice", "stockcode", "description", "quantity",
    "invoicedate", "price", "customer_id", "country",
]
AUDIT_COLUMNS = ["source_file", "source_sheet", "loaded_at"]
ALL_COLUMNS = SOURCE_COLUMNS + AUDIT_COLUMNS

CREATE_TABLE_SQL = f"""
CREATE TABLE IF NOT EXISTS {TARGET_TABLE} (
    invoice       TEXT,
    stockcode     TEXT,
    description   TEXT,
    quantity      TEXT,
    invoicedate   TEXT,
    price         TEXT,
    customer_id   TEXT,
    country       TEXT,
    source_file   TEXT        NOT NULL,
    source_sheet  TEXT        NOT NULL,
    loaded_at     TIMESTAMPTZ NOT NULL
);
"""

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-7s | %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("ingest")


# ---------------------------------------------------------------------------
# 2. Helper functions
# ---------------------------------------------------------------------------
def get_engine():
    """Build a database connection from the values in .env."""
    load_dotenv(PROJECT_ROOT / ".env")
    user = os.getenv("POSTGRES_USER")
    password = os.getenv("POSTGRES_PASSWORD")
    host = os.getenv("POSTGRES_HOST", "localhost")
    port = os.getenv("POSTGRES_PORT", "5434")
    db = os.getenv("POSTGRES_DB")
    if not all([user, password, db]):
        raise RuntimeError("POSTGRES_USER, POSTGRES_PASSWORD or POSTGRES_DB missing from .env")
    return create_engine(f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{db}")


def clean_column_name(name: str) -> str:
    """'Customer ID' -> 'customer_id', 'StockCode' -> 'stockcode'.
    Lower case with no spaces means we never need quotation marks in SQL."""
    return str(name).strip().lower().replace(" ", "_")


def extract(path: Path) -> pd.DataFrame:
    """Read every sheet in the workbook and stack them into one table."""
    if not path.exists():
        raise FileNotFoundError(
            f"Source file not found: {path}\n"
            "Download it from UCI and place it in data/raw/ (see Phase 2, Step 1)."
        )

    log.info("Reading %s (this can take 2 to 5 minutes)...", path.name)
    start = time.time()
    # sheet_name=None -> read ALL sheets, returned as {sheet name: DataFrame}
    # dtype=str       -> keep every value as text, exactly as received
    sheets = pd.read_excel(path, sheet_name=None, dtype=str, engine="openpyxl")
    log.info("Read %d sheet(s) in %.0f seconds", len(sheets), time.time() - start)

    frames = []
    for sheet_name, df in sheets.items():
        df.columns = [clean_column_name(c) for c in df.columns]

        missing = set(SOURCE_COLUMNS) - set(df.columns)
        if missing:
            raise ValueError(f"Sheet '{sheet_name}' is missing columns: {sorted(missing)}")

        df = df[SOURCE_COLUMNS].copy()
        df["source_sheet"] = sheet_name
        log.info("  Sheet '%s': %s rows", sheet_name, f"{len(df):,}")
        frames.append(df)

    combined = pd.concat(frames, ignore_index=True)
    combined["source_file"] = path.name
    # One timestamp for the whole batch, so every row from this run matches.
    combined["loaded_at"] = datetime.now(timezone.utc).isoformat()
    return combined[ALL_COLUMNS]


def load(df: pd.DataFrame, engine) -> None:
    """Replace the Bronze table contents with this batch, inside one transaction."""
    # Write the data into an in-memory CSV file. PostgreSQL's COPY command reads
    # CSV far faster than row-by-row INSERTs (seconds, not many minutes).
    # Empty cells become empty, unquoted fields, which COPY stores as NULL.
    buffer = io.StringIO()
    df.to_csv(buffer, index=False, header=False)
    buffer.seek(0)

    copy_sql = (
        f"COPY {TARGET_TABLE} ({', '.join(ALL_COLUMNS)}) "
        "FROM STDIN WITH (FORMAT csv)"
    )

    log.info("Loading %s rows into %s...", f"{len(df):,}", TARGET_TABLE)
    start = time.time()
    # engine.begin() opens a transaction: everything inside is committed together
    # at the end, or rolled back together if any step fails.
    with engine.begin() as conn:
        conn.execute(text(CREATE_TABLE_SQL))
        conn.execute(text(f"TRUNCATE TABLE {TARGET_TABLE}"))  # empty it first: idempotent
        cursor = conn.connection.cursor()
        cursor.copy_expert(copy_sql, buffer)
        cursor.close()
    log.info("Load committed in %.0f seconds", time.time() - start)


def verify(df: pd.DataFrame, engine) -> bool:
    """Reconcile: do the rows in the database match the rows we read?"""
    with engine.connect() as conn:
        db_total = conn.execute(text(f"SELECT COUNT(*) FROM {TARGET_TABLE}")).scalar()
        per_sheet = conn.execute(text(
            f"SELECT source_sheet, COUNT(*) FROM {TARGET_TABLE} "
            "GROUP BY source_sheet ORDER BY source_sheet"
        )).fetchall()

    log.info("Rows per sheet in the database:")
    for sheet, count in per_sheet:
        log.info("  %-20s %s", sheet, f"{count:,}")

    ok = True
    if db_total != len(df):
        log.error("MISMATCH: read %s rows but the table holds %s", f"{len(df):,}", f"{db_total:,}")
        ok = False
    else:
        log.info("Database total matches rows read: %s", f"{db_total:,}")

    if db_total != EXPECTED_ROWS:
        log.warning("Total differs from the %s rows stated by UCI. Check the file.",
                    f"{EXPECTED_ROWS:,}")
    else:
        log.info("Total matches the UCI published figure of %s", f"{EXPECTED_ROWS:,}")
    return ok


# ---------------------------------------------------------------------------
# 3. Main: Extract -> Load -> Verify
# ---------------------------------------------------------------------------
def main() -> int:
    log.info("=== GiftHub ingestion started ===")
    try:
        engine = get_engine()
        df = extract(SOURCE_FILE)
        load(df, engine)
        ok = verify(df, engine)
    except Exception as exc:
        log.error("Ingestion FAILED: %s", exc)
        return 1

    if not ok:
        log.error("=== Ingestion finished with errors ===")
        return 1
    log.info("=== Ingestion finished successfully ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
