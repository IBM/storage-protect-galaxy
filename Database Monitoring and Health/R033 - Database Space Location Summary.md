# R033 -- Database Space Location Summary

## 1. Overview

Summarizes database space filesystem sizing and distribution across
DBSPACE locations.

## 2. Required Inputs

None.

## 3. Output Details

Filesystem size (MB), Number of DBSPACE locations using each size.

## 4. SQL Query

select TOTAL_FS_SIZE_MB, count(\*) as NUM_LOCATIONS

from dbspace

group by TOTAL_FS_SIZE_MB;

## 5. Purpose for Customers

Helps customers assess DBSPACE layout consistency and storage allocation
strategies.
