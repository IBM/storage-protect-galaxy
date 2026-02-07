# Worst Deduplicated Nodes

**Report ID:** R005

---

## 1. Overview

Identifies the 10 nodes with the lowest deduplication efficiency.

### Purpose

Quickly detect workloads that may require optimization or are not suitable for deduplication. Helps identify inefficient deduplication candidates, understand workload behavior, and take corrective actions such as tuning policies or redesigning data protection strategies.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report analyzes historical backup and archive data |

---

## 3. SQL Query

```sql
SELECT
    SUBSTR(s.ENTITY, 1, 10) AS NODE,
    CAST(FLOAT(SUM(s.bytes_protected)) / 1024 / 1024 / 1024 AS DECIMAL(12, 2)) AS PROTECTED_GB,
    CAST(FLOAT(SUM(s.dedup_savings)) / 1024 / 1024 / 1024 AS DECIMAL(12, 2)) AS DEDUPSAVINGS_GB,
    CAST(FLOAT(SUM(s.comp_savings)) / 1024 / 1024 / 1024 AS DECIMAL(12, 2)) AS COMPSAVINGS_GB,
    CAST(FLOAT(SUM(s.dedup_savings)) / FLOAT(SUM(s.bytes_protected)) * 100 AS DECIMAL(5, 2)) AS DEDUP_PCT,
    CAST(FLOAT(SUM(s.comp_savings)) / FLOAT(SUM(s.bytes_protected) - SUM(s.dedup_savings)) * 100 AS DECIMAL(5, 2)) AS COMP_PCT
FROM
    summary_extended s
WHERE
    DEDUP_SAVINGS <> 0
    AND (activity = 'BACKUP' OR activity = 'ARCHIVE')
GROUP BY
    s.ENTITY
ORDER BY
    DEDUP_PCT ASC
FETCH FIRST
    10 ROWS ONLY;
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `NODE` | String | Node name (truncated to 10 characters) |
| `PROTECTED_GB` | Decimal(12,2) | Protected data (GB) |
| `DEDUPSAVINGS_GB` | Decimal(12,2) | Deduplication savings (GB) |
| `COMPSAVINGS_GB` | Decimal(12,2) | Compression savings (GB) |
| `DEDUP_PCT` | Decimal(5,2) | Deduplication percentage |
| `COMP_PCT` | Decimal(5,2) | Compression percentage |