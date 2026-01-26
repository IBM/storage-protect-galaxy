# R028 -- Storage Pool Capacity and Utilization Summary

## 1. Overview

Summarizes capacity and utilization across all storage pool types.

## 2. Required Inputs

None.

## 3. Output Details

Storage type, Pool type, Number of pools, Total estimated capacity,
Average utilization (%).

## 4. SQL Query

select

stg_type, x

pooltype,

count(\*) as \"NUM_POOLS\",

sum(EST_CAPACITY_MB) as \"ESTCAPACITY\",

(case

when sum(est_capacity_mb)=0 then 0

else sum(est_capacity_mb \* pct_utilized) / sum(est_capacity_mb)

end) as \"AVGPCTUTIL\"

from stgpools

group by stg_type, pooltype;

## 5. Purpose for Customers

Helps customers understand capacity distribution and utilization
efficiency.
