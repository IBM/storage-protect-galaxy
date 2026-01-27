# R005 – Worst Deduplicated Nodes

## Overview
Identifies the **10 nodes with the lowest deduplication efficiency**. This report helps customers quickly detect workloads that may require optimization or are not suitable for deduplication.

## Required Inputs
None.

## Output Details
For each node, the report displays:
- Node name
- Protected data (GB)
- Deduplication savings (GB)
- Compression savings (GB)
- Deduplication percentage
- Compression percentage

## SQL Query
```sql
SELECT SUBSTR(s.ENTITY,1,10) AS NODE,
       CAST(FLOAT(SUM(s.bytes_protected))/1024/1024/1024 AS DECIMAL(12,2)) AS PROTECTED_GB,
       CAST(FLOAT(SUM(s.dedup_savings))/1024/1024/1024 AS DECIMAL(12,2)) AS DEDUPSAVINGS_GB,
       CAST(FLOAT(SUM(s.comp_savings))/1024/1024/1024 AS DECIMAL(12,2)) AS COMPSAVINGS_GB,
       CAST(FLOAT(SUM(s.dedup_savings))/FLOAT(SUM(s.bytes_protected))*100 AS DECIMAL(5,2)) AS DEDUP_PCT,
       CAST(FLOAT(SUM(s.comp_savings))/FLOAT(SUM(s.bytes_protected)-SUM(s.dedup_savings))*100 AS DECIMAL(5,2)) AS COMP_PCT
FROM summary_extended s
WHERE DEDUP_SAVINGS <> 0
  AND (activity = 'BACKUP' OR activity = 'ARCHIVE')
GROUP BY s.ENTITY
ORDER BY DEDUP_PCT ASC
FETCH FIRST 10 ROWS ONLY;
```

## Purpose for Customers
Helps customers identify **inefficient deduplication candidates**, understand workload behavior, and take corrective actions such as tuning policies or redesigning data protection strategies.
