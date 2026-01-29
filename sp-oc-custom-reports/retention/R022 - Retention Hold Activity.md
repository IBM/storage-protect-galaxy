# R022 -- Retention Hold Activity (Past 7 Days)

## 1. Overview

Shows retention sets placed on hold or released from hold during the
last 7 days.

## 2. Required Inputs

None.

## 3. Output Details

Server, Hold name, Event (ADD/RELEASE), Reason.

## 4. SQL Query

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
    r.pitdate DESC;

 ```

## 5. Purpose for Customers

Helps customers support compliance and audit tracking for retention
holds.
