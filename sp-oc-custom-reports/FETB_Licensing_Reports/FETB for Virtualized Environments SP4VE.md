# FETB for Virtualized Environments (SP4VE)

**Report ID:** R005

---

## 1. Overview

Measure front-end capacity for VMs and virtualized workloads.

### Purpose

Provides a focused view of Front-End Terabytes (FETB) capacity specifically for virtualized environments protected by Storage Protect for Virtual Environments (SP4VE). This report helps track VM-specific capacity usage and supports licensing decisions for virtualized workloads.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Filters automatically for API:TSMVM filespace type |

---

## 3. SQL Query

```sql
SELECT
    server,

    CASE
        WHEN vm_type = 1 THEN 'VMWare'
        ELSE ''
    END AS vm_type,

    SUM(COALESCE(fe_capacity, 0)) / 1024 AS fetb_gb

FROM
    tsmgui_allcli_grid

WHERE
    vm_type = 1

GROUP BY
    server,
    vm_type

ORDER BY
    server
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `server` | String | Name of Server |
| `vm_tyoe` | String | Type of VM |
| `fetb_gb` | Decimal | Total front-end capacity in gigabytes (GB) for virtualized workloads |
