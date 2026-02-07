# Storage Pool Utilization

**Report ID:** R006

---

## 1. Overview

Provides a high-level overview of storage pool utilization to identify capacity pressure.

### Purpose

Track pool usage and proactively plan storage expansion. Helps identify pools approaching capacity limits and requiring attention.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report queries current storage pool statistics |

---

## 3. SQL Query

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

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `STGPOOL_NAME` | String | Storage pool name |
| `TOTAL_SAVED_GB` | Decimal | Total space saved (GB) |
| `DEDUP_SAVED_GB` | Decimal | Space saved via deduplication (GB) |
| `COMP_SAVED_GB` | Decimal | Space saved via compression (GB) |
| `USED_SPACE_GB` | Decimal | Used space (GB) |