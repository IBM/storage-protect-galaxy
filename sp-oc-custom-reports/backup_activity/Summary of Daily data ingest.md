# Summary of Daily Data Ingest

**Report ID:** R035

---

## 1. Overview

Summarizes total daily ingest volume processed through backup and archive sessions.

### Purpose

Track overall daily ingest trends and plan capacity. Provides a high-level view of data growth patterns and helps with long-term storage planning.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report analyzes all historical backup data |

---

## 3. SQL Query

```sql 
SELECT
    DATE(s.START_TIME) AS Date,
    CAST(FLOAT(SUM(s.bytes)) / 1024 / 1024 / 1024 AS DECIMAL(12, 2)) AS SESSION_BYTES_GB
FROM
    summary s
WHERE
    activity = 'BACKUP'
    OR activity = 'ARCHIVE'
GROUP BY
    DATE(s.START_TIME)
ORDER BY
    Date DESC;
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `Date` | Date | Backup/archive date |
| `SESSION_BYTES_GB` | Decimal(12,2) | Total ingest volume for the day (GB) |