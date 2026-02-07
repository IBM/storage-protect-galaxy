# Daily Ingest

**Report ID:** R010

---

## 1. Overview

Shows daily protected vs written data along with deduplication and compression savings, aggregated by date.

### Purpose

Track ingest trends and validate data reduction efficiency over time. Useful for capacity planning and identifying days with unusual backup volumes or efficiency changes.

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
| `Date` | Date | Backup date |
| `PROTECTED_GB` | Decimal(12,2) | Total data protected for the day (GB) |
| `WRITTEN_GB` | Decimal(12,2) | Total data written to storage (GB) |
| `DEDUPSAVINGS_GB` | Decimal(12,2) | Total storage saved via deduplication (GB) |
| `COMPSAVINGS_GB` | Decimal(12,2) | Total storage saved via compression (GB) |
| `DEDUP_PCT` | Decimal(5,2) | Deduplication percentage |
| `COMP_PCT` | Decimal(5,2) | Compression percentage |