# Cloud Container Cleanup Status Report

**Report ID:** R026

---

## 1. Overview

Provides visibility into cloud containers that are locked or pending deletion.

### Purpose

Identify cloud pools where cleanup or reclamation may be required. Helps reduce potential cloud storage waste and ensure cleanup processes are functioning correctly.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report runs automatically using cloud container metadata |

---

## 3. SQL Query

```sql 
SELECT
    server,
    name,
    locked_cntrs_pending_30,
    locked_cntrs_pending_bytes_30
FROM
    tsmgui_allstg_grid
WHERE
    locked_cntrs_pending_30 > 0
ORDER BY
    locked_cntrs_pending_bytes_30 DESC
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `server` | String | Server name |
| `name` | String | Cloud pool name |
| `locked_cntrs_pending_30` | Integer | Number of locked containers pending deletion (30 days) |
| `locked_cntrs_pending_bytes_30` | Integer | Size of containers pending deletion in bytes (30 days) |