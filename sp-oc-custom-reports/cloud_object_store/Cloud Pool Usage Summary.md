# Cloud Pool Usage Summary

**Report ID:** R029

---

## 1. Overview

Provides a consolidated view of cloud storage consumption across all cloud-based storage pools, summarizing provisioned and used capacity.

### Purpose

Monitor cloud storage utilization, understand consumption trends, and plan cloud capacity effectively.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report runs automatically using cloud storage pool metadata |

---

## 3. SQL Query

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
    pooltype
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `pooltype` | String | Cloud pool type |
| `NUM_POOLS` | Integer | Number of cloud pools of this type |
| `TOTAL_MB` | Decimal | Total provisioned cloud capacity (MB) |
| `USED_MB` | Decimal | Used cloud capacity (MB) |