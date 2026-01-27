# R037 -- Large Data Movement Summary

## 1. Overview

Summarizes backup or archive operations transferring more than 1 GB in
the last 30 days.

## 2. Required Inputs

None.

## 3. Output Details

Date, Activity type, Total GB transferred.

## 4. SQL Query

```sql SELECT
    DATE(s.START_TIME) AS Date,
    activity,
    CAST(FLOAT(SUM(s.bytes)) / 1024 / 1024 / 1024 AS DECIMAL(12, 2)) AS GB
FROM
    summary s
WHERE
    bytes > 1073741824
    AND s.start_time > DATE(current_timestamp - 30 days)
GROUP BY
    DATE(s.start_time),
    activity;

```

## 5. Purpose for Customers

Helps customers detect unusually large data transfers and capacity
spikes.
