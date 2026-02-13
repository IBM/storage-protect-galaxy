# Top 10 Best Compressed Nodes

**Report ID:** R002

---

## 1. Overview

Identifies client nodes that achieve the highest compression efficiency during backup and archive operations.

### Purpose

Identify workloads with excellent compression efficiency, benchmark performance across nodes, validate compression benefits, and optimize storage utilization strategies.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report runs automatically using backup and archive activity data |

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

    COALESCE(
        CAST(
            FLOAT(SUM(s.comp_savings)) /
            FLOAT(SUM(s.bytes_protected) - SUM(s.dedup_savings)) * 100
            AS DECIMAL(5, 2)
        ),
        0
    ) AS COMP_PCT

FROM
    summary_extended s

WHERE
    activity = 'BACKUP'
    OR activity = 'ARCHIVE'

GROUP BY
    s.ENTITY

ORDER BY
    COMP_PCT DESC

FETCH FIRST
    10 ROWS ONLY
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `NODE` | String | Node name (truncated to 10 characters) |
| `PROTECTED_GB` | Decimal(12,2) | Total protected data (GB) |
| `DEDUPSAVINGS_GB` | Decimal(12,2) | Deduplication savings (GB) |
| `COMPSAVINGS_GB` | Decimal(12,2) | Compression savings (GB) |
| `DEDUP_PCT` | Decimal(5,2) | Deduplication percentage |
| `COMP_PCT` | Decimal(5,2) | Compression percentage |