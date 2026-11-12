-- Databricks notebook source
-- Battery dispatch: the same pipeline as the elt/ folder, but run in Databricks.
-- Personal project on public data, run by hand.
--
-- Before you run it:
--   1. In Databricks open Catalog > workspace > default and create a volume called battery_data.
--      (A volume is just a normal file folder inside Databricks.)
--   2. Upload these two files from the data/ folder of the repo into that volume:
--        belgium_day_ahead_2015_2025.csv
--        elia_total_load_2026-10-16.csv
--   3. Click "Run all".
--
-- The three layers:
--   bronze = raw copy of the files, nothing changed
--   silver = cleaned tables
--   gold   = the table that is ready to use

-- COMMAND ----------

-- Work in UTC (the time zone without summer time), so an "hour" always means the same hour.
SET TIME ZONE 'UTC';

-- COMMAND ----------

-- BRONZE 1: copy the raw price file into a table, without changing anything.
--
-- CREATE OR REPLACE TABLE makes the table, or replaces it if it already exists,
-- so this notebook can be run again and again without doubling the rows.
-- read_files() reads a file from the volume.
-- format => 'csv'  tells it the file is a CSV (values separated by commas).
-- header => true   tells it the first line holds the column names, so it is not a data row.
-- schema => ...    gives the column names and their type. STRING means text.
--                  The raw layer keeps everything as text, the cleaning comes later.
CREATE OR REPLACE TABLE bronze_prices AS
SELECT *
FROM read_files(
  '/Volumes/workspace/default/battery_data/belgium_day_ahead_2015_2025.csv',
  format => 'csv',
  header => true,
  schema => 'ts_utc STRING, currency STRING, eur_per_mwh STRING'
);

-- COMMAND ----------

-- BRONZE 2: copy the raw grid-load file the same way.
-- The file name holds the date it was downloaded from Elia (16 Oct 2026).
-- This file uses a semicolon between the values, so delimiter => ';'.
-- The original column names have spaces in them ("Total Load"), which Databricks tables
-- do not accept, so the schema gives them short names instead.
CREATE OR REPLACE TABLE bronze_load AS
SELECT *
FROM read_files(
  '/Volumes/workspace/default/battery_data/elia_total_load_2026-10-16.csv',
  format => 'csv',
  header => true,
  delimiter => ';',
  schema => 'datetime STRING, resolution_code STRING, total_load STRING,
             most_recent_forecast STRING, most_recent_p10 STRING, most_recent_p90 STRING,
             dayahead_6pm_forecast STRING, dayahead_6pm_p10 STRING, dayahead_6pm_p90 STRING,
             weekahead_forecast STRING'
);

-- COMMAND ----------

-- Count the rows that were loaded. Expected: 102967 price rows and 414140 load rows.
SELECT
  (SELECT count(*) FROM bronze_prices) AS price_rows,
  (SELECT count(*) FROM bronze_load)   AS load_rows;

-- COMMAND ----------

-- SILVER 1: clean hourly prices. These are the same rules as notebook 05 and elt/transform.sql.
-- CAST(... AS TIMESTAMP)       turns the text into a real date and time.
-- CAST(... AS DECIMAL(10, 2))  turns the text into a number with 2 decimals.
-- WHERE ... < 2025-01-01       keeps only prices before 2025, because from 2025 the file
--                              switches from hourly to 15-minute prices.
-- QUALIFY row_number() ... = 1 keeps one row per timestamp. row_number() counts the rows that
--                              share the same timestamp (1, 2, ...), and we keep number 1.
CREATE OR REPLACE TABLE silver_hourly_prices AS
SELECT
  CAST(ts_utc AS TIMESTAMP)          AS ts_utc,
  CAST(eur_per_mwh AS DECIMAL(10,2)) AS price_eur_per_mwh
FROM bronze_prices
WHERE CAST(ts_utc AS TIMESTAMP) < TIMESTAMP '2025-01-01 00:00:00'
QUALIFY row_number() OVER (PARTITION BY CAST(ts_utc AS TIMESTAMP) ORDER BY ts_utc) = 1;

-- COMMAND ----------

-- SILVER 2: hourly grid load. The raw file has one row every 15 minutes,
-- so the four rows of each hour are averaged into one.
-- date_trunc('hour', ...)  cuts a time down to the start of its hour (10:45 becomes 10:00).
-- avg(...)                 is the average of the four 15-minute values.
-- count(*) AS quarter_hours says how many 15-minute rows went into each hour (normally 4).
-- WHERE total_load IS NOT NULL skips rows that have no load value.
-- GROUP BY                 makes one result row per hour.
CREATE OR REPLACE TABLE silver_hourly_load AS
SELECT
  date_trunc('hour', CAST(datetime AS TIMESTAMP)) AS ts_utc,
  avg(CAST(total_load AS DOUBLE))                 AS total_load_mw,
  count(*)                                        AS quarter_hours
FROM bronze_load
WHERE total_load IS NOT NULL
GROUP BY date_trunc('hour', CAST(datetime AS TIMESTAMP));

-- COMMAND ----------

-- GOLD: price and grid load side by side, for the hours that have both.
-- JOIN ... ON puts a price row and a load row together when their hour is the same.
CREATE OR REPLACE TABLE gold_hourly_price_and_load AS
SELECT
  p.ts_utc,
  p.price_eur_per_mwh,
  l.total_load_mw,
  l.quarter_hours
FROM silver_hourly_prices AS p
JOIN silver_hourly_load   AS l ON p.ts_utc = l.ts_utc;

-- COMMAND ----------

-- CHECK: compare silver_hourly_prices with the hourly file the notebooks use.
-- Expected values (taken from that file):
--   row_count 87577, first_hour 2015-01-04 23:00:00, last_hour 2024-12-31 23:00:00,
--   price_sum 6732582.08, lowest_price -500, highest_price 871, duplicate_hours 0.
-- all_ok is true only when every one of those matches.
SELECT
  count(*)                          AS row_count,
  min(ts_utc)                       AS first_hour,
  max(ts_utc)                       AS last_hour,
  sum(price_eur_per_mwh)            AS price_sum,
  min(price_eur_per_mwh)            AS lowest_price,
  max(price_eur_per_mwh)            AS highest_price,
  count(*) - count(DISTINCT ts_utc) AS duplicate_hours,
  count(*) = 87577
    AND min(ts_utc) = TIMESTAMP '2015-01-04 23:00:00'
    AND max(ts_utc) = TIMESTAMP '2024-12-31 23:00:00'
    AND abs(sum(price_eur_per_mwh) - 6732582.08) < 0.01
    AND min(price_eur_per_mwh) = -500
    AND max(price_eur_per_mwh) = 871
    AND count(*) = count(DISTINCT ts_utc) AS all_ok
FROM silver_hourly_prices;

-- COMMAND ----------

-- For information: how complete is the hourly load table?
-- Expected: 103349 hours with 4 rows, 3 hours with 3 rows, 1 hour with 1 row.
SELECT quarter_hours, count(*) AS hours
FROM silver_hourly_load
GROUP BY quarter_hours
ORDER BY quarter_hours;
