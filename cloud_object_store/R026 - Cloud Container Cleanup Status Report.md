# R026 -- Cloud Container Cleanup Status Report

## 1. Overview

The Cloud Container Cleanup Status Report provides visibility into cloud
containers that are locked or pending deletion. It helps identify cloud
pools where cleanup or reclamation may be required.

## 2. Required Inputs

None. The report runs automatically using cloud container metadata.

## 3. Output Details

For each affected cloud pool, the report displays:

\- Server name

\- Cloud pool name

\- Number of locked containers

\- Size of containers pending deletion

## 4. SQL Query

```sql SELECT
    server,
    name,
    locked_cntrs_pending_30,
    locked_cntrs_pending_bytes_30
FROM
    tsmgui_allstg_grid
WHERE
    locked_cntrs_pending_30 > 0
ORDER BY
    locked_cntrs_pending_bytes_30 DESC;

```

## 5. Purpose for Customers

This report helps customers identify cloud pools accumulating locked
containers, reduce potential cloud storage waste, and ensure cleanup
processes are functioning correctly.
