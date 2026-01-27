# R023 -- Expiring Retention Sets (Next N Days)

## 1. Overview

Lists retention sets scheduled to expire within the configured future
window.

## 2. Required Inputs

None.

## 3. Output Details

Set ID, Created by rule, Server, Description, Expiration date, Days
remaining.

## 4. SQL Query

```sql SELECT
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
    r.EXPDATE ASC;

```

## 5. Purpose for Customers

Helps customers prevent accidental expiration of critical retained data.
