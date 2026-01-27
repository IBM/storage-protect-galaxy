# R035 -- Daily Ingest Summary

## 1. Overview

Summarizes total daily ingest volume processed through backup and
archive sessions.

## 2. Required Inputs

None.

## 3. Output Details

Date, Total ingest volume (GB).

## 4. SQL Query

SELECT DATE(s.START_TIME) AS Date,

(CAST(FLOAT(SUM(s.bytes))/1024/1024/1024 AS DECIMAL(12,2))) AS
SESSION_BYTES_GB

FROM summary s

WHERE activity=\'BACKUP\' or activity=\'ARCHIVE\'

GROUP BY DATE(S.START_TIME)

ORDER BY DATE DESC;

## 5. Purpose for Customers

Helps customers track overall daily ingest trends and plan capacity.
