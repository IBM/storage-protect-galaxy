# R036 -- Daily Data Reduction Report

## 1. Overview

The Daily Data Reduction Report provides a day-by-day view of data
protection and reduction efficiency. It shows how much data is protected
versus written and highlights the savings achieved through deduplication
and compression.

## 2. Required Inputs

None. The report is generated automatically from daily backup and
archive activity.

## 3. Output Details

For each day, the report displays:

\- Activity date

\- Total protected data (GB)

\- Actual written data (GB)

\- Deduplication savings (GB)

\- Compression savings (GB)

\- Deduplication percentage

\- Compression percentage

## 4. SQL Query

```sql 
SELECT
    DATE(s.START_TIME) AS Date,

    CAST(FLOAT(SUM(s.bytes_protected)) / 1024 / 1024 / 1024 AS DECIMAL(12, 2)) AS PROTECTED_GB,
    CAST(FLOAT(SUM(s.bytes_written))   / 1024 / 1024 / 1024 AS DECIMAL(12, 2)) AS WRITTEN_GB,
    CAST(FLOAT(SUM(s.dedup_savings))   / 1024 / 1024 / 1024 AS DECIMAL(12, 2)) AS DEDUPSAVINGS_GB,
    CAST(FLOAT(SUM(s.comp_savings))    / 1024 / 1024 / 1024 AS DECIMAL(12, 2)) AS COMPSAVINGS_GB,

    CAST(
        FLOAT(SUM(s.dedup_savings)) / FLOAT(SUM(s.bytes_protected)) * 100
        AS DECIMAL(5, 2)
    ) AS DEDUP_PCT,

    CAST(
        FLOAT(SUM(s.comp_savings)) /
        FLOAT(SUM(s.bytes_protected) - SUM(s.dedup_savings)) * 100
        AS DECIMAL(5, 2)
    ) AS COMP_PCT

FROM
    summary s

WHERE
    activity = 'BACKUP'
    OR activity = 'ARCHIVE'

GROUP BY
    DATE(s.START_TIME)

ORDER BY
    Date DESC;

```

## 5. Purpose for Customers

This report helps customers track daily storage efficiency trends,
understand how much data reduction is achieved over time, detect changes
in backup behavior, and support capacity planning and performance
tuning.
