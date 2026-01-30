# Database Space and Page Utilization Summary

**Report ID:** R031

---

## 1. Overview

Provides a high-level view of database filesystem usage, page utilization, and backup recency.

### Purpose

Monitor database growth, capacity availability, and confirm regular database backups. Helps identify when database expansion may be needed.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report queries current database statistics |

---

## 3. SQL Query

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

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `TOT_FILE_SYSTEM_MB` | Decimal | Total filesystem size allocated for database (MB) |
| `USED_DB_SPACE_MB` | Decimal | Used database space (MB) |
| `FREE_SPACE_MB` | Decimal | Free database space (MB) |
| `TOTAL_PAGES` | Integer | Total database pages |
| `USABLE_PAGES` | Integer | Usable database pages |
| `USED_PAGES` | Integer | Used database pages |
| `FREE_PAGES` | Integer | Free database pages |
| `LAST_BACKUP_DATE` | Date | Last database backup date |