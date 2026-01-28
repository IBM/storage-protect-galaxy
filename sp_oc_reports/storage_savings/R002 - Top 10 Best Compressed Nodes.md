# R002 -- Top 10 Best Compressed Nodes Report

## 1. Overview

The Top 10 Best Compressed Nodes Report identifies client nodes that
achieve the highest compression efficiency during backup and archive
operations. It highlights workloads where compression delivers maximum
data reduction.

## 2. Required Inputs

None. The report runs automatically using backup and archive activity
data.

## 3. Output Details

For each of the top compressed nodes, the report displays:

\- Node name

\- Total protected data (GB)

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

    COALESCE(
        CAST(
            FLOAT(SUM(s.comp_savings)) /
            FLOAT(SUM(s.bytes_protected) - SUM(s.dedup_savings)) * 100
            AS DECIMAL(5, 2)
        ),
        0
    ) AS COMP_PCT

FROM
    summary_extended s

WHERE
    activity = 'BACKUP'
    OR activity = 'ARCHIVE'

GROUP BY
    s.ENTITY

ORDER BY
    COMP_PCT DESC

FETCH FIRST
    10 ROWS ONLY;

```

## 5. Purpose for Customers

This report helps customers identify workloads with excellent
compression efficiency, benchmark performance across nodes, validate
compression benefits, and optimize storage utilization strategies.
