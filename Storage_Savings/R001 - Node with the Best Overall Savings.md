# R001 -- Node with the Best Overall Savings Report

## 1. Overview

The Node with the Best Overall Savings Report identifies client nodes
that achieve the highest overall data reduction through a combination of
deduplication and compression. It highlights the most storage-efficient
nodes in the environment.

## 2. Required Inputs

None. The report runs automatically using backup and archive activity
data.

## 3. Output Details

For each of the top-performing nodes, the report displays:

\- Node name

\- Total protected data (GB)

\- Deduplication savings (GB)

\- Compression savings (GB)

\- Total overall savings (GB)

\- Overall savings percentage

## 4. SQL Query

SELECT SUBSTR(s.ENTITY,1,10) AS NODE,
(CAST(FLOAT(SUM(s.bytes_protected))/1024/1024/1024 AS DECIMAL(12,2))) AS
PROTECTED_GB, (CAST(FLOAT(SUM(s.dedup_savings))/1024/1024/1024 AS
DECIMAL(12,2))) AS DEDUPSAVINGS_GB,
(CAST(FLOAT(SUM(s.comp_savings))/1024/1024/1024 AS DECIMAL(12,2))) AS
COMPSAVINGS_GB,
(CAST(FLOAT(SUM(s.comp_savings)+SUM(s.dedup_savings))/1024/1024/1024 AS
DECIMAL(12,2))) AS OVERALL_SAVINGS_GB,
COALESCE((CAST(FLOAT(SUM(s.dedup_savings)+SUM(s.comp_savings))/FLOAT(SUM(s.bytes_protected))\*100
AS DECIMAL(5,2))),0) AS OVERALL_SAVINGS_PCT FROM summary_extended s
WHERE activity=\'BACKUP\' OR activity=\'ARCHIVE\' GROUP BY s.ENTITY
ORDER BY OVERALL_SAVINGS_PCT DESC FETCH FIRST 10 ROWS ONLY;

## 5. Purpose for Customers

This report helps customers identify clients that deliver the best
storage efficiency, compare backup effectiveness across nodes, validate
deduplication and compression benefits, and use top-performing nodes as
benchmarks for optimization.
