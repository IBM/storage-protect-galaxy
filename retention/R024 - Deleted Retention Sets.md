# R024 -- Deleted Retention Sets (Past 7 Days)

## 1. Overview

Lists retention sets that were deleted by administrators during the past
7 days.

## 2. Required Inputs

None.

## 3. Output Details

Server, Set ID, Description, Rule, Deletion time, Deleted by.

## 4. SQL Query

```sql SELECT
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
    expdate DESC;

```

## 5. Purpose for Customers

Helps customers audit retention deletions and identify risky
administrative actions.
