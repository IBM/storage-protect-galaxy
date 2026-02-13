# Deleted Retention Sets

**Report ID:** R024

---

## 1. Overview

Lists retention sets that were deleted by administrators during the past 7 days.

### Purpose

Audit retention deletions and identify risky administrative actions. Helps maintain compliance and track retention policy changes.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report analyzes deletions from the last 7 days |

---

## 3. SQL Query

```sql 
SELECT
    '%s' AS SERVER,
    id AS ID,
    COALESCE(descr, '') AS DESCR,
    rulename AS RULENAME,
    expdate AS EXPDATE,
    updator AS UPDATOR
FROM
    retsets
WHERE
    state = 'DELETED'
    AND expdate > current timestamp - 1 days
ORDER BY
    expdate DESC
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `SERVER` | String | Server name |
| `ID` | String | Retention set ID |
| `DESCR` | String | Description of the retention set |
| `RULENAME` | String | Rule name associated with the set |
| `EXPDATE` | Timestamp | Deletion time |
| `UPDATOR` | String | Administrator who deleted the set |