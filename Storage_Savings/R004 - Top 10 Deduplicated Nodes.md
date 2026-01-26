# R004 -- Top 10 Deduplicated Nodes Report

## 1. Overview

The Top 10 Deduplicated Nodes Report identifies client nodes that
achieve the highest deduplication efficiency. It highlights workloads
where deduplication provides maximum storage savings.

## 2. Required Inputs

None. The report analyzes backup and archive activity automatically.

## 3. Output Details

For each of the top deduplicated nodes, the report displays:

\- Node name

\- Total protected data (GB)

\- Deduplication savings (GB)

\- Compression savings (GB)

\- Deduplication percentage

\- Compression percentage

## 4. SQL Query

SELECT SUBSTR(s.ENTITY,1,10) AS NODE,
(CAST(FLOAT(SUM(s.bytes_protected))/1024/1024/1024 AS DECIMAL(12,2))) AS
PROTECTED_GB, (CAST(FLOAT(SUM(s.dedup_savings))/1024/1024/1024 AS
DECIMAL(12,2))) AS DEDUPSAVINGS_GB,
(CAST(FLOAT(SUM(s.comp_savings))/1024/1024/1024 AS DECIMAL(12,2))) AS
COMPSAVINGS_GB,
COALESCE((CAST(FLOAT(SUM(s.dedup_savings))/FLOAT(SUM(s.bytes_protected))\*100
AS DECIMAL(5,2))),0) AS DEDUP_PCT,
(CAST(FLOAT(SUM(s.comp_savings))/FLOAT(SUM(s.bytes_protected)-SUM(s.dedup_savings))\*100
AS DECIMAL(5,2))) AS COMP_PCT FROM summary_extended s WHERE
DEDUP_SAVINGS\<\>0 AND activity=\'BACKUP\' OR activity=\'ARCHIVE\' GROUP
BY S.ENTITY ORDER BY DEDUP_PCT DESC FETCH FIRST 10 ROWS ONLY;

## 5. Purpose for Customers

This report helps customers identify nodes with excellent deduplication
performance, compare deduplication effectiveness across workloads,
validate data reduction benefits, and optimize storage efficiency
strategies.
