-- Step 3 of the pipeline: build clean tables from the raw ones.
-- Run:  psql -d battery_dispatch -f elt/transform.sql

-- Work in UTC so that "hour" always means the same thing.
SET TIME ZONE 'UTC';

-- Clean hourly prices. Same rules as notebook 05:
-- keep prices up to the end of 2024 (2025 switches to 15-minute steps),
-- and keep one row per timestamp.
DROP TABLE IF EXISTS hourly_prices;
CREATE TABLE hourly_prices AS
SELECT DISTINCT ON (ts_utc::timestamptz)
       ts_utc::timestamptz        AS ts_utc,
       eur_per_mwh::numeric       AS price_eur_per_mwh
FROM raw_prices
WHERE ts_utc::timestamptz < TIMESTAMPTZ '2025-01-01 00:00:00+00'
ORDER BY ts_utc::timestamptz;

-- Clean hourly grid load: the raw file has one row every 15 minutes,
-- so average the four rows of each hour. quarter_hours says how many rows were used.
DROP TABLE IF EXISTS hourly_load;
CREATE TABLE hourly_load AS
SELECT date_trunc('hour', datetime::timestamptz)  AS ts_utc,
       avg(total_load::numeric)                   AS total_load_mw,
       count(*)                                   AS quarter_hours
FROM raw_load
WHERE total_load IS NOT NULL
GROUP BY date_trunc('hour', datetime::timestamptz)
ORDER BY 1;

-- One table with price and load side by side, for the hours that have both.
DROP TABLE IF EXISTS hourly_price_and_load;
CREATE TABLE hourly_price_and_load AS
SELECT p.ts_utc, p.price_eur_per_mwh, l.total_load_mw, l.quarter_hours
FROM hourly_prices p
JOIN hourly_load l USING (ts_utc)
ORDER BY p.ts_utc;
