# Expiring Retention Sets

**Report ID:** R023

---

## 1. Overview

Lists retention sets scheduled to expire within the next 30 days.

### Purpose

Prevent accidental expiration of critical retained data. Provides early warning for retention sets approaching expiration so appropriate action can be taken.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report looks ahead 30 days by default |

---

## 3. SQL Query

```sql 
SELECT
    t.SETID AS SETID,
    r.RULENAME AS SETCREATEDBY,
    t.SERVER AS SERVER,
    COALESCE(r.DESCR, '') AS DESCRIPTION,
    r.EXPDATE,
    DAYS(r.EXPDATE) - DAYS(current_timestamp) AS DAYSREMAINING
FROM
    retsets r
INNER JOIN
    tsmgui_retsets t
        ON r.id = t.setid
WHERE
    t.SERVER = '%s'
    AND r.EXPDATE < current_timestamp + 30 days
    AND r.EXPDATE > current_timestamp
    AND t.HOLDCOUNT = 0
    AND (t.STATUS = 1 OR t.STATUS = 16)
ORDER BY
    r.EXPDATE ASC
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `SETID` | String | Retention set ID |
| `SETCREATEDBY` | String | Rule name that created this retention set |
| `SERVER` | String | Server name |
| `DESCRIPTION` | String | Description of the retention set |
| `EXPDATE` | Date | Expiration date |
| `DAYSREMAINING` | Integer | Number of days until expiration |