# R007 -- Storage Pool Savings Summary

## 1. Overview

Shows storage pool efficiency using deduplication and compression
savings.

## 2. Required Inputs

None.

## 3. Output Details

Pool name, Space saved %, Space saved (MB), Used space, Dedup savings %,
Compression savings %.

## 4. SQL Query

```sql 
SELECT
    name,
    SPACE_SAVED_PCT,
    SPACE_SAVED_MB,
    USED_SPACE,
    DEDUP_SAVED_MB,
    DEDUP_SAVED_PCT,
    COMP_SAVED_MB,
    COMP_SAVED_PCT
FROM
    TSMGUI_ALLSTG_GRID
WHERE
    STG_TYPE = 101
    OR STG_TYPE = 100
ORDER BY
    SPACE_SAVED_PCT DESC;

```

## 5. Purpose for Customers

Helps customers identify highly efficient or underperforming storage
pools.
