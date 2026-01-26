# R009 -- Summarized Node Backups (Last 24 Hours)

## 1. Overview

Provides an aggregated summary of backup activity per node in the last
24 hours.

## 2. Required Inputs

None.

## 3. Output Details

Node name, Total protected data (MB), Written data (MB), Dedup savings
(MB), Compression savings (MB), Deduplication %.

## 4. SQL Query

SELECT Entity AS NODE_NAME,
(CAST(FLOAT(SUM(s.bytes_protected))/1024/1024 AS DECIMAL(12,2))) AS
PROTECTED_MB, (CAST(FLOAT(SUM(s.bytes_written))/1024/1024 AS
DECIMAL(12,2))) AS WRITTEN_MB,
(CAST(FLOAT(SUM(s.dedup_savings))/1024/1024 AS DECIMAL(12,2))) AS
DEDUPSAVINGS_MB, (CAST(FLOAT(SUM(s.comp_savings))/1024/1024 AS
DECIMAL(12,2))) AS COMPSAVINGS_MB,
(CAST(FLOAT(SUM(s.dedup_savings))/FLOAT(SUM(s.bytes_protected))\*100 AS
DECIMAL(5,2))) AS DEDUP_PCT FROM

summary s WHERE s.bytes_protected\<\>0 AND (activity=\'BACKUP\' OR
activity=\'ARCHIVE\') AND s.START_TIME\>=(current_date - 1 days) GROUP
BY ENTITY ORDER BY COMPSAVINGS_MB DESC;

## 5. Purpose for Customers

Helps customers quickly identify nodes with high backup volume and
savings.
