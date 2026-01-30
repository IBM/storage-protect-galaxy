# Highest Rate of Backup Failure

**Report ID:** R013

---

## 1. Overview

Identifies standard clients with the highest backup failure percentage in the last 24 hours.

### Purpose

Quickly identify problematic clients requiring investigation. Shows the top 10 clients with the worst backup success rates to prioritize troubleshooting efforts.

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
    clients.type,
    rate,
    fail_table.server
FROM (
    SELECT
        a.node_name,
        ROUND(CAST(failed AS FLOAT) / total_sys * 100.0, 1) AS rate,
        '%s' AS server
    FROM (
        SELECT
            name AS node_name,
            COUNT(name) AS failed
        FROM
            summary s
        INNER JOIN
            tsmgui_allcli_grid
                ON entity = name
        WHERE
            (activity = 'BACKUP' OR activity = 'ARCHIVE')
            AND status > 0
            AND successful = 'NO'
        GROUP BY
            name
    ) a
    INNER JOIN (
        SELECT
            name AS node_name,
            COUNT(name) AS total_sys
        FROM
            summary s
        INNER JOIN
            tsmgui_allcli_grid
                ON entity = name
        WHERE
            (activity = 'BACKUP' OR activity = 'ARCHIVE')
        GROUP BY
            name
    ) b
        ON a.node_name = b.node_name
) fail_table
INNER JOIN
    tsmgui_allcli_grid clients
        ON fail_table.node_name = clients.name
        AND fail_table.server = clients.server
ORDER BY
    rate DESC
FETCH FIRST
    10 ROWS ONLY;
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `node_name` | String | Client node name |
| `type` | String | Client type (e.g., TDP, BA Client) |
| `rate` | Decimal | Backup failure rate percentage |
| `server` | String | Storage Protect server name |