# Power BI

Files for the Power BI report on the gold table (`hourly_price_and_load`).

- `hourly_price_and_load.csv`: the data, written by `elt/export_gold.sql` (hourly price and grid load, UTC).
  It is not committed to GitHub (see `.gitignore`), so create it with:
  `psql -d battery_dispatch -f elt/export_gold.sql`
- `DAX_measures.md`: the DAX measures and the numbers to check the report against.
- The Power BI report (`battery-dispatch.pbix`) is kept on the local computer and is not committed (see `.gitignore`), because it holds a copy of the price data.
