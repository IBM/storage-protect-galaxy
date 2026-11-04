# Node Backups in the Last N Hours

**Report ID:** R008

---

## 1. Overview

Provides detailed backup activity for each node over the last 24 hours, including protected data volumes, written data, and efficiency metrics such as deduplication and compression savings.

### Purpose

Monitor recent backup activity and efficiency per node. Helps identify backup operations, analyze data protection efficiency, and validate that critical nodes are being backed up regularly.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report analyzes the last 24 hours automatically |

---

## 3. SQL Query

```sql 
SELECT
    ENTITY AS NODE_NAME,
    s.START_TIME,

    CAST(FLOAT(s.bytes_protected) / 1024 / 1024 AS DECIMAL(12, 2)) AS PROTECTED_MB,
    CAST(FLOAT(s.bytes_written)   / 1024 / 1024 AS DECIMAL(12, 2)) AS WRITTEN_MB,
    CAST(FLOAT(s.dedup_savings)   / 1024 / 1024 AS DECIMAL(12, 2)) AS DEDUPSAVINGS_MB,
    CAST(FLOAT(s.comp_savings)    / 1024 / 1024 AS DECIMAL(12, 2)) AS COMPSAVINGS_MB,

    CAST(
        FLOAT(s.dedup_savings) / FLOAT(s.bytes_protected) * 100
        AS DECIMAL(5, 2)
    ) AS DEDUP_PCT

FROM
    summary s

WHERE
    s.bytes_protected <> 0
    AND (activity = 'BACKUP' OR activity = 'ARCHIVE')
    AND s.START_TIME >= (current_date - 1 days)

ORDER BY
    COMPSAVINGS_MB DESC
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `NODE_NAME` | String | Client node name |
| `START_TIME` | Timestamp | Backup start time |
| `PROTECTED_MB` | Decimal(12,2) | Total data protected (MB) |
| `WRITTEN_MB` | Decimal(12,2) | Data written to storage (MB) |
| `DEDUPSAVINGS_MB` | Decimal(12,2) | Storage saved via deduplication (MB) |
| `COMPSAVINGS_MB` | Decimal(12,2) | Storage saved via compression (MB) |
| `DEDUP_PCT` | Decimal(5,2) | Deduplication percentage |