# R029 -- Cloud Pool Usage Summary Report

## 1. Overview

The Cloud Pool Usage Summary Report provides a consolidated view of
cloud storage consumption across all cloud-based storage pools. It
summarizes provisioned and used capacity to help monitor cloud usage.

## 2. Required Inputs

None. The report runs automatically using cloud storage pool metadata.

## 3. Output Details

For each cloud pool type, the report displays:

\- Cloud pool type

\- Number of cloud pools

\- Total provisioned cloud capacity (MB)

\- Used cloud capacity (MB)

## 4. SQL Query

```sql 
SELECT
    pooltype,
    COUNT(*) AS "NUM_POOLS",
    SUM(TOTAL_CLOUD_SPACE_MB) AS "TOTAL_MB",
    SUM(USED_CLOUD_SPACE_MB) AS "USED_MB"
FROM
    stgpools
WHERE
    stg_type = 'CLOUD'
GROUP BY
    pooltype;

```

## 5. Purpose for Customers

This report helps customers monitor cloud storage utilization,
understand consumption trends, and plan cloud capacity effectively.
