"""
Phase 1 check: confirms Python on your machine can reach the warehouse
and that the bronze, silver and gold schemas exist.

Run from the project root:
    python ingestion/test_connection.py
"""
import os
import sys

from dotenv import load_dotenv
from sqlalchemy import create_engine, text

load_dotenv()  # reads the .env file in the project root

user = os.getenv("POSTGRES_USER")
password = os.getenv("POSTGRES_PASSWORD")
host = os.getenv("POSTGRES_HOST", "localhost")
port = os.getenv("POSTGRES_PORT", "5433")
db = os.getenv("POSTGRES_DB")

engine = create_engine(f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{db}")

EXPECTED = {"bronze", "silver", "gold"}

try:
    with engine.connect() as conn:
        version = conn.execute(text("SELECT version()")).scalar()
        rows = conn.execute(text(
            "SELECT schema_name FROM information_schema.schemata "
            "WHERE schema_name IN ('bronze', 'silver', 'gold') ORDER BY schema_name"
        )).fetchall()
except Exception as exc:
    print("FAILED: could not connect to PostgreSQL.")
    print(f"Reason: {exc}")
    print("Check that Docker is running and `docker compose ps` shows postgres as healthy.")
    sys.exit(1)

found = {r[0] for r in rows}
print("Connected to:", version.split(",")[0])
print("Schemas found:", ", ".join(sorted(found)) or "none")

missing = EXPECTED - found
if missing:
    print("FAILED: missing schemas:", ", ".join(sorted(missing)))
    sys.exit(1)

print("SUCCESS: Phase 1 database setup is complete.")
