# Top 10 Least Compressed Nodes

**Report ID:** R003

---

## 1. Overview

Identifies nodes with the lowest compression efficiency.

### Purpose

Pinpoint data sources that may require tuning or configuration review. Helps identify nodes with poor compression efficiency, assess data types or workloads that compress poorly, and improve overall storage efficiency.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report uses historical backup and archive data automatically |

---

## 3. SQL Query

```sql 
SELECT
    SUBSTR(s.ENTITY, 1, 10) AS NODE,

    CAST(FLOAT(SUM(s.bytes_protected)) / 1024 / 1024 / 1024 AS DECIMAL(12, 2)) AS PROTECTED_GB,
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
    summary_extended s

WHERE
    activity = 'BACKUP'
    OR activity = 'ARCHIVE'

GROUP BY
    s.ENTITY

ORDER BY
    COMP_PCT ASC

FETCH FIRST
    10 ROWS ONLY;
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `NODE` | String | Node name (truncated to 10 characters) |
| `PROTECTED_GB` | Decimal(12,2) | Total protected data size (GB) |
| `DEDUPSAVINGS_GB` | Decimal(12,2) | Deduplication savings (GB) |
| `COMPSAVINGS_GB` | Decimal(12,2) | Compression savings (GB) |
| `DEDUP_PCT` | Decimal(5,2) | Deduplication percentage |
| `COMP_PCT` | Decimal(5,2) | Compression percentage |