# Detailed Virtualized Workload FETB

**Report ID:** R006

---

## 1. Overview

Capture per-node, per-platform FETB for virtualization including SP4VE flag.

### Purpose

Provides a comprehensive breakdown of Front-End Terabytes (FETB) capacity for virtualized workloads, grouped by platform, operating system, and hypervisor type. The report includes an SP4VE flag to identify workloads protected by Storage Protect for Virtual Environments, enabling detailed capacity analysis and licensing management for virtualized environments.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Automatically filters for nodes with capacity > 0 |

---

## 3. SQL Query

```sql
SELECT 
  platform_name, 
  client_os_name, 
  hypervisor, 
  sp4ve, 
  CAST(SUM(fe_mb) AS DECIMAL(12,2)) AS fe_mb
FROM (
  SELECT 
    n.node_name, 
    platform_name, 
    client_os_name, 
    hypervisor, 
    (CASE WHEN filespace_type='API:TSMVM' THEN 'TRUE' ELSE '' END) AS sp4ve,
    SUM(fecapacity)/1024/1024 AS fe_mb
  FROM filespaces f
  JOIN nodes n ON n.node_name = f.node_name
  GROUP BY n.node_name, platform_name, client_os_name, hypervisor, filespace_type
) t
WHERE fe_mb > 0
GROUP BY platform_name, client_os_name, hypervisor, sp4ve
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `platform_name` | String | Platform type of the nodes |
| `client_os_name` | String | Operating system name of the clients |
| `hypervisor` | String | Hypervisor type for virtualized workloads |
| `sp4ve` | String | SP4VE flag: 'TRUE' if protected by Storage Protect for Virtual Environments, empty otherwise |
| `fe_mb` | Decimal | Total front-end capacity in megabytes (MB) for the combination |
