# FETB by Platform / Workload

**Report ID:** R003

---

## 1. Overview

Measure FETB per platform and OS for reporting and audits.

### Purpose

Provides an aggregated view of Front-End Terabytes (FETB) capacity grouped by platform and operating system. This report is valuable for understanding capacity distribution across different platforms, supporting audit requirements, and making platform-specific licensing decisions.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | No input parameters required |

---

## 3. SQL Query

```sql
SELECT 
  n.platform_name,
  n.client_os_name,
  SUM(COALESCE(f.fecapacity, 0)) / 1024 / 1024 / 1024 AS fetb_gb
FROM nodes n
JOIN filespaces f ON n.node_name = f.node_name
GROUP BY n.platform_name, n.client_os_name
ORDER BY fetb_gb DESC;
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `platform_name` | String | Platform type of the nodes |
| `client_os_name` | String | Operating system name of the clients |
| `fetb_gb` | Decimal | Total front-end capacity in gigabytes (GB) for the platform/OS combination |