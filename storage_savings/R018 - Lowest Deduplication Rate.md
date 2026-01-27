# R018 -- Lowest Deduplication Rate Report

## 1. Overview

The Lowest Deduplication Rate Report identifies client nodes with the
poorest deduplication efficiency during recent backup operations. It
highlights workloads that generate highly unique data and therefore
achieve minimal deduplication savings.

## 2. Required Inputs

None. The report runs automatically using recent backup and archive
activity data.

## 3. Output Details

For each client with the lowest deduplication efficiency, the report
displays:

\- Client node name

\- Server name

\- Deduplication percentage

\- Client type (for example, file system, VM guest, or API)

## 4. SQL Query

```sql SELECT
    node,
    a.server,
    dedup_pct,
    type
FROM (
    SELECT
        SUBSTR(s.entity, 1, 10) AS node,
        CAST(
            FLOAT(SUM(s.dedup_savings)) /
            FLOAT(SUM(s.bytes_protected)) * 100
            AS DECIMAL(5, 2)
        ) AS dedup_pct,
        '%s' AS server
    FROM
        summary_extended s
    WHERE
        dedup_savings <> 0
        AND (activity = 'BACKUP' OR activity = 'ARCHIVE')
        AND end_time >= (current_timestamp - 24 hours)
    GROUP BY
        s.entity
    ORDER BY
        dedup_pct ASC
    FETCH FIRST
        10 ROWS ONLY
) a
INNER JOIN
    tsmgui_allcli_grid b
        ON a.node = b.name
        AND a.server = b.server
ORDER BY
    dedup_pct ASC;

```

## 5. Purpose for Customers

This report helps customers detect workloads that benefit little from
deduplication, validate deduplication configuration, understand data
characteristics such as encrypted or compressed data, and improve
storage planning for low-dedup workloads.
