# Summarized Node Backups in the Last N Hours

**Report ID:** R009

---

## 1. Overview

Provides an aggregated summary of backup activity per node in the last 24 hours, combining multiple backup sessions into a single summary per node.

### Purpose

Quickly identify nodes with high backup volume and savings. Useful for high-level capacity planning and identifying nodes with best/worst compression and deduplication efficiency.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report analyzes the last 24 hours automatically |

---

## 3. SQL Query

```sql 
SELECT
    Entity AS NODE_NAME,

    CAST(FLOAT(SUM(s.bytes_protected)) / 1024 / 1024 AS DECIMAL(12, 2)) AS PROTECTED_MB,
    CAST(FLOAT(SUM(s.bytes_written))   / 1024 / 1024 AS DECIMAL(12, 2)) AS WRITTEN_MB,
    CAST(FLOAT(SUM(s.dedup_savings))   / 1024 / 1024 AS DECIMAL(12, 2)) AS DEDUPSAVINGS_MB,
    CAST(FLOAT(SUM(s.comp_savings))    / 1024 / 1024 AS DECIMAL(12, 2)) AS COMPSAVINGS_MB,

    CAST(
        FLOAT(SUM(s.dedup_savings)) / FLOAT(SUM(s.bytes_protected)) * 100
        AS DECIMAL(5, 2)
    ) AS DEDUP_PCT

FROM
    summary s

WHERE
    s.bytes_protected <> 0
    AND (activity = 'BACKUP' OR activity = 'ARCHIVE')
    AND s.START_TIME >= (current_date - 1 days)

GROUP BY
    ENTITY

ORDER BY
    COMPSAVINGS_MB DESC
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `NODE_NAME` | String | Client node name |
| `PROTECTED_MB` | Decimal(12,2) | Total data protected across all backups (MB) |
| `WRITTEN_MB` | Decimal(12,2) | Total data written to storage (MB) |
| `DEDUPSAVINGS_MB` | Decimal(12,2) | Total storage saved via deduplication (MB) |
| `COMPSAVINGS_MB` | Decimal(12,2) | Total storage saved via compression (MB) |
| `DEDUP_PCT` | Decimal(5,2) | Overall deduplication percentage |