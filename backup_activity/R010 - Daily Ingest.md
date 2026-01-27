# R010 -- Daily Ingest Report

## 1. Overview

Shows daily protected vs written data along with deduplication and
compression savings.

## 2. Required Inputs

None.

## 3. Output Details

Date, Protected data (GB), Written data (GB), Dedup savings (GB),
Compression savings (GB), Dedup %, Comp %.

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

Helps track ingest trends and validate data reduction efficiency over
time.
