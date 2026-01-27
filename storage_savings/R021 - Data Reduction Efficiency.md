# R021 -- Data Reduction Efficiency Report

## 1. Overview

The Data Reduction Efficiency Report provides a consolidated view of how
effectively storage is reduced across servers using deduplication and
compression. It summarizes overall data reduction efficiency to help
customers evaluate storage optimization.

## 2. Required Inputs

None. The report runs automatically using container-based storage
metrics.

## 3. Output Details

For each server, the report displays:

\- Server name

\- Physical used capacity

\- Deduplication savings

\- Compression savings

\- Total logical data size

\- Deduplication percentage

\- Compression percentage

\- Total data reduction percentage

## 4. SQL Query

SELECT server,
       dedup,
       comp,
       used,
       (used + dedup + comp) AS total,
       ROUND(
            CASE WHEN used = 0 THEN 0
                 ELSE CAST(comp AS FLOAT) / (used + dedup + comp) * 100.0
            END, 1
       ) AS comp_pct,
       ROUND(
            CASE WHEN numPools = 1 THEN dedupSaved
                 ELSE CAST(dedup AS FLOAT) / (used + dedup + comp) * 100.0
            END, 1
       ) AS dedup_pct
FROM (
        SELECT server,
               SUM(used_space) * 1024 AS used,
               SUM(COALESCE(DEDUP_SAVED_MB, 0)) AS dedup,
               SUM(COALESCE(comp_saved_mb, 0)) AS comp,
               COUNT(name) AS numPools,
               SUM(DEDUP_SAVED_PCT) AS dedupSaved
        FROM tsmgui_allstg_grid
        WHERE (DEDUP_SAVED_PCT IS NOT NULL AND DEDUP_SAVED_PCT <> 0)
           OR (COMP_SAVED_PCT IS NOT NULL AND COMP_SAVED_PCT <> 0)
        GROUP BY server
     )
ORDER BY dedup_pct DESC; 

## 5. Purpose for Customers

This report helps customers compare data reduction efficiency across
servers, identify underperforming environments, validate deduplication
and compression benefits, and support capacity planning decisions.
