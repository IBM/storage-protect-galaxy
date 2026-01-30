# Database Space Path Breakdown

**Report ID:** R034

---

## 1. Overview

Provides a detailed breakdown of each database storage path, including total size, used space, and remaining free space.

### Purpose

Identify uneven DBSPACE utilization and plan database capacity expansion. Helps pinpoint which paths need attention for space management.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report queries current database configuration |

---

## 3. SQL Query

```sql 
SELECT
    PATH_NUMBER,
    TOTAL_FS_SIZE_MB,
    USED_FS_SIZE_MB,
    FREE_SPACE_MB
FROM
    DBSPACE;
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `PATH_NUMBER` | Integer | Database path number |
| `TOTAL_FS_SIZE_MB` | Decimal | Total filesystem size for this path (MB) |
| `USED_FS_SIZE_MB` | Decimal | Used space on this path (MB) |
| `FREE_SPACE_MB` | Decimal | Free space remaining on this path (MB) |