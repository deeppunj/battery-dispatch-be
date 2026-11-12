# DAX measures

DAX is the formula language of Power BI. A **measure** is a formula that is worked out again for every
chart, depending on what the chart shows (one year, one hour of the day, and so on).

Data table: `hourly_price_and_load` (one row per hour, loaded from `hourly_price_and_load.csv`).
Times are UTC. Prices are in EUR/MWh and load is in MW (megawatts).

## 1. Calendar table (Modeling > New table)

A calendar table has one row per day. It lets charts group the hourly data by year and month.

```dax
Date =
ADDCOLUMNS (
    CALENDAR ( DATE ( 2015, 1, 4 ), DATE ( 2024, 12, 31 ) ),  // one row per day, first to last day of the data
    "Year", YEAR ( [Date] ),                                    // 2015, 2016, ...
    "Month number", MONTH ( [Date] ),                           // 1 to 12, only used to sort the month names
    "Month", FORMAT ( [Date], "MMM" )                           // Jan, Feb, ...
)
```

After creating it: select the `Month` column, then Column tools > Sort by column > `Month number`.
Otherwise the months are sorted alphabetically (Apr, Aug, Dec ...).

## 2. Measures (Modeling > New measure, one at a time)

```dax
Average Price =
AVERAGE ( hourly_price_and_load[price_eur_per_mwh] )   // mean of the hourly prices that the chart shows
```

```dax
Max Price =
MAX ( hourly_price_and_load[price_eur_per_mwh] )       // highest hourly price
```

```dax
Min Price =
MIN ( hourly_price_and_load[price_eur_per_mwh] )       // lowest hourly price
```

```dax
Average Load =
AVERAGE ( hourly_price_and_load[total_load_mw] )       // mean grid load in MW
```

```dax
Negative Price Hours =
COALESCE (                                              // COALESCE swaps an empty result for 0
    CALCULATE (                                         // CALCULATE counts with an extra filter added
        COUNTROWS ( hourly_price_and_load ),            // count the hours (each row is one hour)
        hourly_price_and_load[price_eur_per_mwh] < 0    // ...but only the hours with a price below zero
    ),
    0
)
```

```dax
Share of Negative Hours =
DIVIDE (                                                // DIVIDE avoids an error when the divisor is 0
    [Negative Price Hours],                             // hours with a negative price
    COUNTROWS ( hourly_price_and_load )                 // all hours in the chart
)
```
Format: Measure tools > Format > Percentage, 2 decimals.

```dax
Average Daily Price Spread =
AVERAGEX (                                              // calculate something per day, then average the results
    VALUES ( 'Date'[Date] ),                            // the days that the chart shows
    CALCULATE (                                         // for each day:
        MAX ( hourly_price_and_load[price_eur_per_mwh] )    // highest price of that day
        - MIN ( hourly_price_and_load[price_eur_per_mwh] )  // minus lowest price of that day
    )
)
```
The daily spread is what a battery earns from: it charges in the cheap hours and sells in the expensive ones.

## 3. Numbers to check your report against

With no filter (all years), the cards should show:

| Measure | Expected value |
|---|---|
| Average Price | 76.88 EUR/MWh |
| Max Price / Min Price | 871 / -500 |
| Average Load | 9,602 MW |
| Negative Price Hours | 1,121 |
| Share of Negative Hours | 1.28% |
| Average Daily Price Spread | 68.47 EUR/MWh |

Negative-price hours by year: 2016: 2, 2017: 6, 2018: 9, 2019: 71, 2020: 136, 2021: 159, 2022: 113, 2023: 221, 2024: 404.

These were calculated from the CSV file with Python, so a difference means a mistake in the model or a measure.
