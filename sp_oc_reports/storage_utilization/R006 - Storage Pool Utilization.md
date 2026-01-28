# R006 -- Storage Pool Utilization Overview

## 1. Overview

Provides a high-level overview of storage pool utilization to identify
capacity pressure.

## 2. Required Inputs

None.

## 3. Output Details

Storage pool name, Utilized capacity, Free capacity, Utilization
percentage.

## 4. SQL Query

```sql 
SELECT
    STGPOOL_NAME,
    CAST(SPACE_SAVED_MB AS FLOAT)        / 1024 AS TOTAL_SAVED_GB,
    CAST(DEDUP_SPACE_SAVED_MB AS FLOAT) / 1024 AS DEDUP_SAVED_GB,
    CAST(COMP_SPACE_SAVED_MB AS FLOAT)  / 1024 AS COMP_SAVED_GB,
    (CAST(EST_CAPACITY_MB AS FLOAT) / 1024) * PCT_UTILIZED / 100 AS USED_SPACE_GB
FROM
    stgpools
WHERE
    STG_TYPE = 'DIRECTORY'
    OR STG_TYPE = 'CLOUD'
ORDER BY
    TOTAL_SAVED_GB DESC;

```

## 5. Purpose for Customers

Helps customers track pool usage and proactively plan storage expansion.
