# Data Reduction Efficiency

**Report ID:** R021

---

## 1. Overview

Provides a consolidated view of how effectively storage is reduced across servers using deduplication and compression.

### Purpose

Compare data reduction efficiency across servers, identify underperforming environments, validate deduplication and compression benefits, and support capacity planning decisions.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report runs automatically using container-based storage metrics |

---

## 3. SQL Query

```sql 
SELECT
    server,
    dedup,
    comp,
    used,
    (used + dedup + comp) AS total,
    ROUND(
        CASE
            WHEN used = 0 THEN 0
            ELSE CAST(comp AS FLOAT) / (used + dedup + comp) * 100.0
        END,
        1
    ) AS comp_pct,
    ROUND(
        CASE
            WHEN numPools = 1 THEN dedupSaved
            ELSE CAST(dedup AS FLOAT) / (used + dedup + comp) * 100.0
        END,
        1
    ) AS dedup_pct
FROM (
    SELECT
        server,
        SUM(used_space) * 1024 AS used,
        SUM(COALESCE(DEDUP_SAVED_MB, 0)) AS dedup,
        SUM(COALESCE(comp_saved_mb, 0)) AS comp,
        COUNT(name) AS numPools,
        SUM(DEDUP_SAVED_PCT) AS dedupSaved
    FROM
        tsmgui_allstg_grid
    WHERE
        (DEDUP_SAVED_PCT IS NOT NULL AND DEDUP_SAVED_PCT <> 0)
        OR (COMP_SAVED_PCT IS NOT NULL AND COMP_SAVED_PCT <> 0)
    GROUP BY
        server
)
ORDER BY
    dedup_pct DESC;
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `server` | String | Server name |
| `dedup` | Integer | Deduplication savings (MB) |
| `comp` | Integer | Compression savings (MB) |
| `used` | Integer | Physical used capacity (MB) |
| `total` | Integer | Total logical data size (MB) |
| `comp_pct` | Decimal | Compression percentage |
| `dedup_pct` | Decimal | Deduplication percentage |