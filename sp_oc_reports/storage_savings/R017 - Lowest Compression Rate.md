# R017 -- Lowest Compression Rate Report

## 1. Overview

The Lowest Compression Rate Report identifies client nodes with the
poorest compression efficiency during recent backup operations. It
highlights workloads that do not benefit from compression and may
increase overall storage consumption.

## 2. Required Inputs

None. The report runs using recent backup and archive activity data.

## 3. Output Details

For each client with the lowest compression efficiency, the report
displays:

\- Client node name

\- Server name

\- Effective compression percentage

\- Client type (for example, file system, VM guest, or agent)

## 4. SQL Query

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
    comp_pct ASC;

```

## 5. Purpose for Customers

This report helps customers detect clients generating poorly
compressible data, validate compression configurations, tune backup
strategies, and reduce unnecessary storage growth.
