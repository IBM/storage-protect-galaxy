# Large Data Movement Summary

**Report ID:** R037

---

## 1. Overview

Summarizes backup or archive operations transferring more than 1 GB in the last 30 days.

### Purpose

Detect unusually large data transfers and capacity spikes. Helps identify potential issues with backup jobs or unusual data growth patterns.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report analyzes operations from the last 30 days |

---

## 3. SQL Query

```sql 
SELECT
    DATE(s.START_TIME) AS Date,
    activity,
    CAST(FLOAT(SUM(s.bytes)) / 1024 / 1024 / 1024 AS DECIMAL(12, 2)) AS GB
FROM
    summary s
WHERE
    bytes > 1073741824
    AND s.start_time > DATE(current_timestamp - 30 days)
GROUP BY
    DATE(s.start_time),
    activity
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `Date` | Date | Date of activity |
| `activity` | String | Activity type (BACKUP/ARCHIVE) |
| `GB` | Decimal(12,2) | Total GB transferred on that date |