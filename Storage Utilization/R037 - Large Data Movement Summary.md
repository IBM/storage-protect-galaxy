# R037 -- Large Data Movement Summary

## 1. Overview

Summarizes backup or archive operations transferring more than 1 GB in
the last 30 days.

## 2. Required Inputs

None.

## 3. Output Details

Date, Activity type, Total GB transferred.

## 4. SQL Query

select DATE(s.START_TIME) AS Date, activity,

(CAST(FLOAT(SUM(s.bytes))/1024/1024/1024 AS DECIMAL(12,2))) AS GB

from summary s

where bytes \> 1073741824

and s.start_time \> date(current timestamp - 30 days)

group by date(s.start_time), activity;

## 5. Purpose for Customers

Helps customers detect unusually large data transfers and capacity
spikes.
