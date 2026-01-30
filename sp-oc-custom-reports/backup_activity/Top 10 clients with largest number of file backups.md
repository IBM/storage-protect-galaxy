# Top 10 Clients with Largest Number of File Backups

**Report ID:** R016

---

## 1. Overview

Identifies clients backing up the highest number of files in the last 24 hours.

### Purpose

Detect workloads with high file churn and inefficient backup patterns. Helps identify clients that may benefit from backup policy adjustments or file exclusions.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report analyzes the last 24 hours automatically |

---

## 3. SQL Query

```sql 
SELECT
    node_name,
    a.server,
    files,
    type
FROM (
    SELECT
        node_name,
        files,
        '%s' AS server
    FROM (
        SELECT
            name AS node_name,
            COALESCE(SUM(affected), 0) AS files
        FROM
            summary s
        INNER JOIN
            tsmgui_allcli_grid
                ON entity = name
        WHERE
            (activity = 'BACKUP' OR activity = 'ARCHIVE')
            AND s.end_time >= (current_timestamp - 24 hours)
        GROUP BY
            name
        ORDER BY
            files DESC
        FETCH FIRST
            10 ROWS ONLY
    )
) a
INNER JOIN
    tsmgui_allcli_grid b
        ON a.node_name = b.name
        AND a.server = b.server;
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `node_name` | String | Client node name |
| `server` | String | Storage Protect server name |
| `files` | Integer | Total number of files backed up |
| `type` | String | Client type (e.g., TDP, BA Client) |