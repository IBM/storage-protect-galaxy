# Lowest Compression Rate

**Report ID:** R017

---

## 1. Overview

Identifies client nodes with the poorest compression efficiency during recent backup operations.

### Purpose

Detect clients generating poorly compressible data, validate compression configurations, tune backup strategies, and reduce unnecessary storage growth.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report uses recent backup and archive activity data (last 24 hours) |

---

## 3. SQL Query

```sql 
SELECT
    node,
    a.server,
    comp_pct,
    type
FROM (
    SELECT
        SUBSTR(s.entity, 1, 10) AS node,
        CAST(
            FLOAT(SUM(s.comp_savings)) /
            FLOAT(SUM(s.bytes_protected) - SUM(s.dedup_savings)) * 100
            AS DECIMAL(5, 2)
        ) AS comp_pct,
        '%s' AS server
    FROM
        summary_extended s
    WHERE
        (activity = 'BACKUP' OR activity = 'ARCHIVE')
        AND (s.bytes_protected - s.dedup_savings) > 1000000  -- ignore tiny backups
        AND end_time >= (current_timestamp - 24 hours)
    GROUP BY
        s.entity
    ORDER BY
        comp_pct ASC
    FETCH FIRST
        10 ROWS ONLY
) a
INNER JOIN
    tsmgui_allcli_grid b
        ON a.node = b.name
        AND a.server = b.server
ORDER BY
    comp_pct ASC
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `node` | String | Client node name (truncated to 10 characters) |
| `server` | String | Server name |
| `comp_pct` | Decimal(5,2) | Effective compression percentage |
| `type` | String | Client type (e.g., file system, VM guest, agent) |