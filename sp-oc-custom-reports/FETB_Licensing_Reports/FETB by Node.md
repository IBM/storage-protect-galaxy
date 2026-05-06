# FETB by Node

**Report ID:** R002

---

## 1. Overview

See FETB per node for capacity planning or reporting.

### Purpose

Provides a detailed breakdown of Front-End Terabytes (FETB) capacity for each individual node in the system. This report is essential for capacity planning, identifying high-capacity nodes, and generating node-specific licensing reports.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | No input parameters required |

---

## 3. SQL Query

```sql
SELECT 
  n.node_name,
  n.platform_name,
  SUM(COALESCE(f.fecapacity, 0)) / 1024 / 1024 / 1024 AS fetb_gb
FROM nodes n
JOIN filespaces f ON n.node_name = f.node_name
GROUP BY n.node_name, n.platform_name
ORDER BY fetb_gb DESC;
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `node_name` | String | Name of the node |
| `platform_name` | String | Platform/operating system of the node |
| `fetb_gb` | Decimal | Front-end capacity in gigabytes (GB) for the node |