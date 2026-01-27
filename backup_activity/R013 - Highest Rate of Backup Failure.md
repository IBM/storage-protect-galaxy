# R013 -- Highest Backup Failure Rate (Clients)

## 1. Overview

Identifies standard clients with the highest backup failure percentage
in the last 24 hours.

## 2. Required Inputs

None.

## 3. Output Details

Client name, Client type, Failure %, Server.

## 4. SQL Query

```sql SELECT
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

## 5. Purpose for Customers

Helps identify problematic clients requiring investigation.
