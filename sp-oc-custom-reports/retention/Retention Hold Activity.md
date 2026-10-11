# Retention Hold Activity

**Report ID:** R022

---

## 1. Overview

Shows retention sets placed on hold or released from hold during the last 7 days.

### Purpose

Support compliance and audit tracking for retention holds. Helps maintain visibility into legal holds and retention policy changes.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report analyzes retention activity from the last 7 days |

---

## 3. SQL Query

```sql 
SELECT
    '%s' AS SERVER,
    h.HOLDNAME AS HOLDNAME,
    h.ACTION AS EVENT,
    h.REASON AS REASON
FROM
    holdlog h
INNER JOIN
    retsets r
        ON h.retsetid = r.id
WHERE
    h.datetime > current_timestamp - 1 days
ORDER BY
    r.pitdate DESC
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `SERVER` | String | Server name |
| `HOLDNAME` | String | Name of the retention hold |
| `EVENT` | String | Hold action (ADD/RELEASE) |
| `REASON` | String | Reason for the hold action |