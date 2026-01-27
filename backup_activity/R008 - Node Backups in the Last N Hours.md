# R008 -- Node Backups in the Last 24 Hours

## 1. Overview

Provides detailed backup activity for each node over the last 24 hours.

## 2. Required Inputs

None.

## 3. Output Details

Node name, Backup start time, Protected data (MB), Written data (MB),
Dedup savings (MB), Compression savings (MB), Deduplication %.

## 4. SQL Query

```sql SELECT
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
    COMPSAVINGS_MB DESC;
```

## 5. Purpose for Customers

Helps customers review recent backup activity and efficiency per node.
