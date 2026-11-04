# Node with the Best Overall Savings

**Report ID:** R001

---

## 1. Overview

Identifies client nodes that achieve the highest overall data reduction through a combination of deduplication and compression.

### Purpose

Identify clients that deliver the best storage efficiency, compare backup effectiveness across nodes, validate deduplication and compression benefits, and use top-performing nodes as benchmarks for optimization.

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
        FLOAT(SUM(s.comp_savings) + SUM(s.dedup_savings)) / 1024 / 1024 / 1024
        AS DECIMAL(12, 2)
    ) AS OVERALL_SAVINGS_GB,

    COALESCE(
        CAST(
            FLOAT(SUM(s.dedup_savings) + SUM(s.comp_savings)) /
            FLOAT(SUM(s.bytes_protected)) * 100
            AS DECIMAL(5, 2)
        ),
        0
    ) AS OVERALL_SAVINGS_PCT

FROM
    summary_extended s

WHERE
    activity = 'BACKUP'
    OR activity = 'ARCHIVE'

GROUP BY
    s.ENTITY

ORDER BY
    OVERALL_SAVINGS_PCT DESC

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
| `OVERALL_SAVINGS_GB` | Decimal(12,2) | Total overall savings (GB) |
| `OVERALL_SAVINGS_PCT` | Decimal(5,2) | Overall savings percentage |