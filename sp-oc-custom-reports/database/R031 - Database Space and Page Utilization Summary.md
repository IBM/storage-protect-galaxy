# R031 -- Database Space and Page Utilization Summary

## 1. Overview

Provides a high-level view of database filesystem usage, page
utilization, and backup recency.

## 2. Required Inputs

None.

## 3. Output Details

Total filesystem size, Used DB space, Free DB space, Total pages, Used
pages, Free pages, Last backup date.

## 4. SQL Query

```sql 
SELECT
    TOT_FILE_SYSTEM_MB,
    USED_DB_SPACE_MB,
    FREE_SPACE_MB,
    TOTAL_PAGES,
    USABLE_PAGES,
    USED_PAGES,
    FREE_PAGES,
    LAST_BACKUP_DATE
FROM
    db;

```

## 5. Purpose for Customers

Helps customers monitor database growth, capacity availability, and
confirm regular database backups.
