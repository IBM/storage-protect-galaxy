# Storage Utilization Summary

**Report ID:** R011

---

## 1. Overview

Provides a consolidated view of storage utilization across storage pools and servers, highlighting total capacity, used space, free space, and utilization percentage.

### Purpose

Identify storage capacity pressure, monitor pool utilization trends, and proactively plan storage expansion or rebalancing.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report queries current storage pool statistics |

---

## 3. SQL Query

```sql 
SELECT
    name,
    server,
    PCT_UTIL,
    (1024 * TOTAL_SPACE) AS total,
    (1024 * USED_SPACE) AS used,
    (1024 * FREE_SPACE) AS free,
    type,
    stg_type
FROM
    TSMGUI_ALLSTG_GRID
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `name` | String | Storage pool name |
| `server` | String | Server name |
| `PCT_UTIL` | Decimal | Utilization percentage |
| `total` | Decimal | Total capacity (MB) |
| `used` | Decimal | Used capacity (MB) |
| `free` | Decimal | Free capacity (MB) |
| `type` | String | Storage pool type |
| `stg_type` | Integer | Storage technology code (disk, file, container, cloud, tape) |