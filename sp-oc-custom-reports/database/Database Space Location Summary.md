# Database Space Location Summary

**Report ID:** R033

---

## 1. Overview

Summarizes database space filesystem sizing and distribution across DBSPACE locations.

### Purpose

Assess DBSPACE layout consistency and storage allocation strategies. Helps identify whether database storage is evenly distributed or if consolidation is needed.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report queries current database configuration |

---

## 3. SQL Query

```sql 
SELECT
    TOTAL_FS_SIZE_MB,
    COUNT(*) AS NUM_LOCATIONS
FROM
    dbspace
GROUP BY
    TOTAL_FS_SIZE_MB;
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `TOTAL_FS_SIZE_MB` | Decimal | Filesystem size (MB) |
| `NUM_LOCATIONS` | Integer | Number of DBSPACE locations using this filesystem size |