# Storage Pool Savings Summary

**Report ID:** R007

---

## 1. Overview

Shows storage pool efficiency using deduplication and compression savings.

### Purpose

Identify highly efficient or underperforming storage pools. Helps prioritize optimization efforts and validate data reduction benefits.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report queries current storage pool statistics |

---

## 3. SQL Query

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
    SPACE_SAVED_PCT DESC
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `name` | String | Storage pool name |
| `SPACE_SAVED_PCT` | Decimal | Total space saved percentage |
| `SPACE_SAVED_MB` | Decimal | Total space saved (MB) |
| `USED_SPACE` | Decimal | Used space (MB) |
| `DEDUP_SAVED_MB` | Decimal | Deduplication savings (MB) |
| `DEDUP_SAVED_PCT` | Decimal | Deduplication savings percentage |
| `COMP_SAVED_MB` | Decimal | Compression savings (MB) |
| `COMP_SAVED_PCT` | Decimal | Compression savings percentage |