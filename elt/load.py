# Step 2 of the pipeline: load the raw CSV files into PostgreSQL, unchanged.
# Run from the repository root:  python elt/load.py
# Every column is stored as text on purpose. Cleaning happens later in transform.sql.

import glob
import os
from pathlib import Path

import psycopg2

# Connection settings. Change the database name if you called it something else.
DB_NAME = os.environ.get("PGDATABASE", "battery_dispatch")
DB_HOST = os.environ.get("PGHOST", "localhost")
DB_PORT = os.environ.get("PGPORT", "5432")
DB_USER = os.environ.get("PGUSER", os.environ.get("USER", ""))
DB_PASSWORD = os.environ.get("PGPASSWORD", "")

# The repository folder is one level above this elt folder. Using it for the file paths means
# this script works wherever it is started from (terminal or the PyCharm Run button).
ROOT = Path(__file__).resolve().parent.parent

PRICE_FILE = ROOT / "data" / "belgium_day_ahead_2015_2025.csv"
# The load files are named elia_total_load_<download date>.csv, so sorting by name puts the
# newest download last. Use the newest one. extract.py creates these files.
downloads = sorted(glob.glob(str(ROOT / "data" / "elia_total_load_*.csv")))
if not downloads:
    raise SystemExit("No data/elia_total_load_*.csv file found. Run extract.py first.")
LOAD_FILE = downloads[-1]

# Table definitions: the column names follow the CSV headers.
CREATE_RAW_PRICES = """
DROP TABLE IF EXISTS raw_prices;
CREATE TABLE raw_prices (
    ts_utc        text,
    currency      text,
    eur_per_mwh   text
);
"""

CREATE_RAW_LOAD = """
DROP TABLE IF EXISTS raw_load;
CREATE TABLE raw_load (
    datetime               text,
    resolution_code        text,
    total_load             text,
    most_recent_forecast   text,
    most_recent_p10        text,
    most_recent_p90        text,
    dayahead_6pm_forecast  text,
    dayahead_6pm_p10       text,
    dayahead_6pm_p90       text,
    weekahead_forecast     text
);
"""


def copy_csv(cursor, table, path, delimiter):
    # COPY reads the whole file in one go; HEADER skips the first line.
    with open(path, "r", encoding="utf-8-sig") as f:
        cursor.copy_expert(
            f"COPY {table} FROM STDIN WITH (FORMAT csv, HEADER true, DELIMITER '{delimiter}')",
            f,
        )
    cursor.execute(f"SELECT count(*) FROM {table}")
    print(f"{table}: {cursor.fetchone()[0]:,} rows loaded from {path}")


def main():
    connection = psycopg2.connect(
        dbname=DB_NAME, host=DB_HOST, port=DB_PORT, user=DB_USER, password=DB_PASSWORD
    )
    with connection:
        with connection.cursor() as cursor:
            # Dropping and re-creating the tables means a second run
            # gives the same result and never doubles the rows.
            cursor.execute(CREATE_RAW_PRICES)
            copy_csv(cursor, "raw_prices", PRICE_FILE, ",")
            cursor.execute(CREATE_RAW_LOAD)
            copy_csv(cursor, "raw_load", LOAD_FILE, ";")
    connection.close()


if __name__ == "__main__":
    main()
