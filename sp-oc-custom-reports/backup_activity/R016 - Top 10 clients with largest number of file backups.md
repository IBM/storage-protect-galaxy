# R016 -- Clients with Most Files Backed Up

## 1. Overview

Identifies clients backing up the highest number of files in the last 24
hours.

## 2. Required Inputs

None.

## 3. Output Details

Client name, Files backed up, Client type, Server.

## 4. SQL Query

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

## 5. Purpose for Customers

Helps detect workloads with high file churn and inefficient backup
patterns.
