# R012 -- Client Backup Status (Last N Hours)

## 1. Overview

Provides a summary of client backup success and failure across servers
for a configurable time window.

## 2. Required Inputs

None. Defaults to last 24 hours.

## 3. Output Details

Server name, Success %, Failure %, Total backups, Failed backups,
Successful backups.

## 4. SQL Query

```sql 
SELECT
    '%s' AS server,
    ROUND(CAST(total_failed  AS FLOAT) / total * 100.0, 1) AS pct_failed,
    ROUND(CAST(total_success AS FLOAT) / total * 100.0, 1) AS pct_success,
    total,
    total_failed,
    total_success
FROM (
    SELECT
        COUNT(name) AS total,
        SUM(CASE WHEN SUCCESSFUL = 'NO' THEN 1 ELSE 0 END) AS total_failed,
        SUM(CASE WHEN SUCCESSFUL <> 'NO' THEN 1 ELSE 0 END) AS total_success
    FROM (
        SELECT
            t.NAME,
            s.END_TIME,
            s.SUCCESSFUL
        FROM
            summary s
        INNER JOIN
            tsmgui_allcli_grid t
                ON s.ENTITY = t.NAME
        WHERE
            (activity = 'BACKUP' OR activity = 'ARCHIVE')
            AND s.END_TIME >= (current_timestamp - 24 hours)
            AND TYPE = 1

        UNION ALL

        SELECT
            t.NAME,
            s.END_TIME,
            s.SUCCESSFUL
        FROM
            summary_extended s
        INNER JOIN
            tsmgui_allcli_grid t
                ON s.ENTITY = t.NAME
        WHERE
            activity = 'BACKUP'
            AND activity_type = 'SESSION_END'
            AND s.ACTIVITY_DETAILS = 'SESSION_LIST: ' || s.NUMBER
            AND s.END_TIME >= (current_timestamp - 24 hours)
            AND TYPE = 0

        UNION ALL

        SELECT
            t.NAME,
            e.END_TIME,
            e.SUCCESSFUL
        FROM
            summary_extended e
        INNER JOIN
            tsmgui_allcli_grid t
                ON e.SUB_ENTITY = t.NAME
        WHERE
            e.activity = 'BACKUP'
            AND e.END_TIME >= (current_timestamp - 24 hours)
            AND (
                e.ACTIVITY_TYPE = 'Full'
                OR e.ACTIVITY_TYPE LIKE 'Incremental%'
            )
            AND e.SUB_ENTITY IS NOT NULL

        UNION ALL

        SELECT
            t.NAME,
            ev.SCHEDULED_START AS END_TIME,
            'NO' AS SUCCESSFUL
        FROM
            events ev
        INNER JOIN
            tsmgui_allcli_grid t
                ON ev.NODE_NAME = t.NAME
        WHERE
            ev.SCHEDULED_START >= (current_timestamp - 24 hours)
            AND ev.STATUS = 'Missed'
    )
)
WHERE
    total > 0;

```

## 5. Purpose for Customers

Helps verify backup health and quickly identify servers with elevated
failures.
