# Storage Pool Capacity and Utilization Summary

**Report ID:** R028

---

## 1. Overview

Summarizes capacity and utilization across all storage pool types.

### Purpose

Understand capacity distribution and utilization efficiency. Helps with strategic planning for storage infrastructure and identifying pool type trends.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report queries current storage pool statistics |

---

## 3. SQL Query

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

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `stg_type` | String | Storage type (e.g., DIRECTORY, CLOUD, FILE) |
| `pooltype` | String | Pool type classification |
| `NUM_POOLS` | Integer | Number of pools of this type |
| `ESTCAPACITY` | Decimal | Total estimated capacity (MB) |
| `AVGPCTUTIL` | Decimal | Average utilization percentage |