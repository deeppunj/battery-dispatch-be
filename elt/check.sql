-- Step 4 of the pipeline: check the new hourly_prices table against the file
-- the notebooks use today (data/belgium_day_ahead_hourly_2015_2024.csv).
-- Run:  psql -d battery_dispatch -f elt/check.sql
-- The "expected" numbers were taken from that file. Every ok column should say true.

SET TIME ZONE 'UTC';

SELECT 'rows'        AS check_name,
       count(*)::text AS from_database,
       '87577'        AS expected,
       count(*) = 87577 AS ok
FROM hourly_prices
UNION ALL
SELECT 'first hour', min(ts_utc)::text, '2015-01-04 23:00:00+00',
       min(ts_utc) = TIMESTAMPTZ '2015-01-04 23:00:00+00'
FROM hourly_prices
UNION ALL
SELECT 'last hour', max(ts_utc)::text, '2024-12-31 23:00:00+00',
       max(ts_utc) = TIMESTAMPTZ '2024-12-31 23:00:00+00'
FROM hourly_prices
UNION ALL
SELECT 'sum of prices', sum(price_eur_per_mwh)::text, '6732582.08',
       abs(sum(price_eur_per_mwh) - 6732582.08) < 0.01
FROM hourly_prices
UNION ALL
SELECT 'lowest price', min(price_eur_per_mwh)::text, '-500.0',
       min(price_eur_per_mwh) = -500.0
FROM hourly_prices
UNION ALL
SELECT 'highest price', max(price_eur_per_mwh)::text, '871.0',
       max(price_eur_per_mwh) = 871.0
FROM hourly_prices
UNION ALL
-- No hour may appear twice.
SELECT 'duplicate hours', (count(*) - count(DISTINCT ts_utc))::text, '0',
       count(*) = count(DISTINCT ts_utc)
FROM hourly_prices;

-- For information: how complete is the hourly load table?
SELECT quarter_hours, count(*) AS hours
FROM hourly_load
GROUP BY quarter_hours
ORDER BY quarter_hours;
