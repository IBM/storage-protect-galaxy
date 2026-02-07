# Lowest Deduplication Rate

**Report ID:** R018

---

## 1. Overview

Identifies client nodes with the poorest deduplication efficiency during recent backup operations.

### Purpose

Detect workloads that benefit little from deduplication, validate deduplication configuration, understand data characteristics such as encrypted or compressed data, and improve storage planning for low-dedup workloads.

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

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `node` | String | Client node name (truncated to 10 characters) |
| `server` | String | Server name |
| `dedup_pct` | Decimal(5,2) | Deduplication percentage |
| `type` | String | Client type (e.g., file system, VM guest, API) |# Lowest Deduplication Rate

**Report ID:** R018

---

## 1. Overview

Identifies client nodes with the poorest deduplication efficiency during recent backup operations.

### Purpose

Detect workloads that benefit little from deduplication, validate deduplication configuration, understand data characteristics such as encrypted or compressed data, and improve storage planning for low-dedup workloads.

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

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `node` | String | Client node name (truncated to 10 characters) |
| `server` | String | Server name |
| `dedup_pct` | Decimal(5,2) | Deduplication percentage |
| `type` | String | Client type (e.g., file system, VM guest, API) |