# R015 -- Clients with Most Data Backed Up

## 1. Overview

Identifies clients backing up the largest volume of data in the last 24
hours.

## 2. Required Inputs

None.

## 3. Output Details

Client name, Client type, Total backup size, Server.

## 4. SQL Query

```sql SELECT
    node_name,
    type,
    size,
    '%s' AS server
FROM (
    (
        SELECT
            name AS node_name,
            type,
            SUM(
                CASE
                    WHEN COALESCE(BYTES_PROTECTED, 0) > 0
                        THEN COALESCE(BYTES_PROTECTED, 0)
                    ELSE
                        COALESCE(BYTES, 0)
                END
            ) AS size
        FROM
            summary s
        INNER JOIN
            tsmgui_allcli_grid
                ON entity = name
        WHERE
            (activity = 'BACKUP' OR activity = 'ARCHIVE')
            AND s.end_time >= (current_timestamp - 24 hours)
        GROUP BY
            name,
            type
        ORDER BY
            size DESC
        FETCH FIRST
            10 ROWS ONLY
    )

    UNION

    (
        SELECT
            name AS node_name,
            type,
            COALESCE(SUM(bytes), 0) AS size
        FROM
            summary_extended s
        INNER JOIN
            tsmgui_allcli_grid
                ON sub_entity = name
        WHERE
            activity = 'BACKUP'
            AND s.end_time >= (current_timestamp - 24 hours)
            AND (
                activity_type = 'Full'
                OR activity_type LIKE 'Incremental%'
            )
            AND sub_entity IS NOT NULL
        GROUP BY
            name,
            type
        ORDER BY
            size DESC
        FETCH FIRST
            10 ROWS ONLY
    )
)
ORDER BY
    size DESC
FETCH FIRST
    10 ROWS ONLY;

```

## 5. Purpose for Customers

Helps identify high-volume data generators and plan capacity.
