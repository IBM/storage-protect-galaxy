<img width="468" height="551" alt="image" src="https://github.com/user-attachments/assets/68908197-7248-4ec2-9264-36a0e917a1c4" /># Detailed Virtualized Workload FETB

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

```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `platform` | String | Platform type of the nodes |
| `hypervisor` | String | Hypervisor type for virtualized workloads |
| `sp4ve` | String | SP4VE flag: 'TRUE' if protected by Storage Protect for Virtual Environments, empty otherwise |
| `fe_mb` | Decimal | Total front-end capacity in megabytes (MB) for the combination |
