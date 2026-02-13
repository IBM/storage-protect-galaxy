# Database Protect Master Key Status

**Report ID:** R032

---

## 1. Overview

Shows the status of the Protect Master Key used for securing encrypted database objects.

### Purpose

Verify that database encryption key protection is enabled. Critical for ensuring database security compliance.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report queries current database configuration |

---

## 3. SQL Query

```sql 
SELECT
    PROTECT_MASTER_KEY
FROM
    db
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `PROTECT_MASTER_KEY` | String | Status of Protect Master Key (ON/OFF) |