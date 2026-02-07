# Daily Data Reduction

**Report ID:** R036

---

## 1. Overview

Provides a day-by-day view of data protection and reduction efficiency, showing how much data is protected versus written and highlighting savings achieved through deduplication and compression.

### Purpose

Track daily storage efficiency trends, understand how much data reduction is achieved over time, detect changes in backup behavior, and support capacity planning and performance tuning.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report generated automatically from daily backup and archive activity |

---

## 3. SQL Query

```sql 
SELECT
    DATE(s.START_TIME) AS Date,

    CAST(FLOAT(SUM(s.bytes_protected)) / 1024 / 1024 / 1024 AS DECIMAL(12, 2)) AS PROTECTED_GB,
    CAST(FLOAT(SUM(s.bytes_written))   / 1024 / 1024 / 1024 AS DECIMAL(12, 2)) AS WRITTEN_GB,
    CAST(FLOAT(SUM(s.dedup_savings))   / 1024 / 1024 / 1024 AS DECIMAL(12, 2)) AS DEDUPSAVINGS_GB,
    CAST(FLOAT(SUM(s.comp_savings))    / 1024 / 1024 / 1024 AS DECIMAL(12, 2)) AS COMPSAVINGS_GB,

    CAST(
        FLOAT(SUM(s.dedup_savings)) / FLOAT(SUM(s.bytes_protected)) * 100
        AS DECIMAL(5, 2)
    ) AS DEDUP_PCT,

    CAST(
        FLOAT(SUM(s.comp_savings)) /
        FLOAT(SUM(s.bytes_protected) - SUM(s.dedup_savings)) * 100
        AS DECIMAL(5, 2)
    ) AS COMP_PCT

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
| `Date` | Date | Activity date |
| `PROTECTED_GB` | Decimal(12,2) | Total protected data (GB) |
| `WRITTEN_GB` | Decimal(12,2) | Actual written data (GB) |
| `DEDUPSAVINGS_GB` | Decimal(12,2) | Deduplication savings (GB) |
| `COMPSAVINGS_GB` | Decimal(12,2) | Compression savings (GB) |
| `DEDUP_PCT` | Decimal(5,2) | Deduplication percentage |
| `COMP_PCT` | Decimal(5,2) | Compression percentage |