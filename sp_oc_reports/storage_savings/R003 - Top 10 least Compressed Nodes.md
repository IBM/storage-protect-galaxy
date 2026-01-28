# R003 -- Top 10 Worst Compressed Nodes Report

## 1. Overview

The Top 10 Worst Compressed Nodes Report identifies nodes with the
lowest compression efficiency. It highlights nodes where compression
benefits are minimal, helping customers pinpoint data sources that may
require tuning or configuration review.

## 2. Required Inputs

None. The report uses historical backup and archive data automatically.

## 3. Output Details

For each of the worst-performing nodes, the report displays:

\- Node name

\- Total protected data size (GB)

\- Deduplication savings (GB)

\- Compression savings (GB)

\- Deduplication percentage

\- Compression percentage

## 4. SQL Query

```sql 
SELECT
    SUBSTR(s.ENTITY, 1, 10) AS NODE,

    CAST(FLOAT(SUM(s.bytes_protected)) / 1024 / 1024 / 1024 AS DECIMAL(12, 2)) AS PROTECTED_GB,
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
    summary_extended s

WHERE
    activity = 'BACKUP'
    OR activity = 'ARCHIVE'

GROUP BY
    s.ENTITY

ORDER BY
    COMP_PCT ASC

FETCH FIRST
    10 ROWS ONLY;

```

## 5. Purpose for Customers

This report helps customers identify nodes with poor compression
efficiency, assess data types or workloads that compress poorly,
optimize backup policies, and improve overall storage efficiency.
