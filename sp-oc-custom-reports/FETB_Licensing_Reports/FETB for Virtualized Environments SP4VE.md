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
  f.filespace_type,
  SUM(COALESCE(f.fecapacity, 0)) / 1024 / 1024 / 1024 AS fetb_gb
FROM filespaces f
WHERE f.filespace_type = 'API:TSMVM'
GROUP BY f.filespace_type
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `filespace_type` | String | Type of filespace (API:TSMVM for virtualized environments) |
| `fetb_gb` | Decimal | Total front-end capacity in gigabytes (GB) for virtualized workloads |
