# Summary of Most Data Backed Up

**Report ID:** R015

---

## 1. Overview

Identifies clients backing up the largest volume of data in the last 24 hours.

### Purpose

Identify high-volume data generators and plan capacity. Helps understand which clients consume the most storage resources and may require special attention for performance optimization.

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

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `node_name` | String | Client node name |
| `type` | String | Client type (e.g., TDP, BA Client) |
| `size` | Integer | Total backup size in bytes |
| `server` | String | Storage Protect server name |