# R028 -- Storage Pool Capacity and Utilization Summary

## 1. Overview

Summarizes capacity and utilization across all storage pool types.

## 2. Required Inputs

None.

## 3. Output Details

Storage type, Pool type, Number of pools, Total estimated capacity,
Average utilization (%).

## 4. SQL Query

```sql 
SELECT
    stg_type,
    pooltype,
    COUNT(*) AS "NUM_POOLS",
    SUM(EST_CAPACITY_MB) AS "ESTCAPACITY",
    CASE
        WHEN SUM(est_capacity_mb) = 0 THEN 0
        ELSE SUM(est_capacity_mb * pct_utilized) / SUM(est_capacity_mb)
    END AS "AVGPCTUTIL"
FROM
    stgpools
GROUP BY
    stg_type,
    pooltype;

```

## 5. Purpose for Customers

Helps customers understand capacity distribution and utilization
efficiency.
