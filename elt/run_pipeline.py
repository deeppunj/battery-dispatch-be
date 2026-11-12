# Runs the whole pipeline in one go: load, transform, check, export.
# In PyCharm: open this file and click the green Run button. No terminal needed.
# (extract.py is separate: run it first only when you want a fresh download from Elia.)

from pathlib import Path

import psycopg2

import load  # load.py in the same folder. It also holds the database settings.

# The repository folder is one level above this elt folder.
ROOT = Path(__file__).resolve().parent.parent
ELT = ROOT / "elt"

# The query that export_gold.sql runs with psql, written here for Python.
EXPORT_QUERY = """
SELECT ts_utc AT TIME ZONE 'UTC' AS ts_utc, price_eur_per_mwh, total_load_mw, quarter_hours
FROM hourly_price_and_load
ORDER BY ts_utc
"""


def read_statements(path):
    # Read a .sql file and cut it into single statements.
    lines = path.read_text().splitlines()
    # Throw away the comment lines (they start with two dashes).
    code = "\n".join(line for line in lines if not line.strip().startswith("--"))
    # Every statement ends with a semicolon, so cut there and skip empty pieces.
    return [piece.strip() for piece in code.split(";") if piece.strip()]


def print_rows(cursor):
    # Print the result of a SELECT as a small table: column names first, then the rows.
    names = [column[0] for column in cursor.description]
    print(" | ".join(names))
    for row in cursor.fetchall():
        print(" | ".join(str(value) for value in row))
    print()


def run_sql_file(cursor, path):
    print(f"--- {path.name}")
    for statement in read_statements(path):
        cursor.execute(statement)
        # A SELECT gives rows back (cursor.description is filled), so print them.
        # CREATE TABLE and SET give nothing back.
        if cursor.description is not None:
            print_rows(cursor)


def export_gold(cursor):
    # Write the gold table to a CSV file for Power BI.
    output_file = ROOT / "powerBi" / "hourly_price_and_load.csv"
    output_file.parent.mkdir(exist_ok=True)  # make the powerBi folder if it is missing
    with open(output_file, "w") as f:
        # COPY ... TO STDOUT sends the query result as CSV text, and copy_expert writes it into f.
        cursor.copy_expert(f"COPY ({EXPORT_QUERY}) TO STDOUT WITH CSV HEADER", f)
    print(f"--- export: saved {output_file}")


def main():
    # Step 2: load the raw files into PostgreSQL (the code is in load.py).
    load.main()

    # Steps 3 to 5 need a database connection, using the same settings as load.py.
    connection = psycopg2.connect(
        dbname=load.DB_NAME, host=load.DB_HOST, port=load.DB_PORT,
        user=load.DB_USER, password=load.DB_PASSWORD,
    )
    # "with connection" saves (commits) everything if no error happens, otherwise it rolls back.
    with connection:
        with connection.cursor() as cursor:
            run_sql_file(cursor, ELT / "transform.sql")  # step 3: build the clean tables
            run_sql_file(cursor, ELT / "check.sql")      # step 4: every ok should say True
            export_gold(cursor)                          # step 5: write the CSV for Power BI
    connection.close()


if __name__ == "__main__":
    main()
