# R011 -- Storage Utilization Summary

## 1. Overview

Provides a consolidated view of storage utilization across storage pools
and servers, highlighting total capacity, used space, free space, and
utilization percentage.

## 2. Required Inputs

None.

## 3. Output Details

For each server and storage pool, the report displays:

\- Server name

\- Storage pool name and type

\- Storage technology (disk, file, container, cloud, tape)

\- Total capacity

\- Used capacity

\- Free capacity

\- Utilization percentage

## 4. SQL Query

```sql SELECT
    name,
    server,
    PCT_UTIL,
    (1024 * TOTAL_SPACE) AS total,
    (1024 * USED_SPACE) AS used,
    (1024 * FREE_SPACE) AS free,
    type,
    stg_type
FROM
    TSMGUI_ALLSTG_GRID;

```

## 5. Purpose for Customers

Helps customers identify storage capacity pressure, monitor pool
utilization trends, and proactively plan storage expansion or
rebalancing.
