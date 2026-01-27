# R034 -- Database Space Path Breakdown

## 1. Overview

Provides a detailed breakdown of each database storage path, including
total size, used space, and remaining free space.

## 2. Required Inputs

None.

## 3. Output Details

Path number, Total filesystem size (MB), Used space (MB), Free space
(MB).

## 4. SQL Query

```sql 
SELECT
    PATH_NUMBER,
    TOTAL_FS_SIZE_MB,
    USED_FS_SIZE_MB,
    FREE_SPACE_MB
FROM
    DBSPACE;

```

## 5. Purpose for Customers

Helps customers identify uneven DBSPACE utilization and plan database
capacity expansion.
