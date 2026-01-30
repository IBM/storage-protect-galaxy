# Node Storage Consumption Summary

**Report ID:** R030

---

## 1. Overview

Provides a summary of storage pool configuration and consumption metrics.

### Purpose

Identify top storage-consuming configurations and understand storage pool characteristics including encryption status and reuse policies.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report queries current storage pool configuration |

---

## 3. SQL Query

```sql 
SELECT
    devclass,
    pooltype,
    est_capacity_mb,
    pct_utilized,
    encrypted,
    pct_encrypted,
    reusedelay
FROM
    stgpools;
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `devclass` | String | Device class name |
| `pooltype` | String | Pool type classification |
| `est_capacity_mb` | Decimal | Estimated capacity (MB) |
| `pct_utilized` | Decimal | Utilization percentage |
| `encrypted` | String | Encryption status (YES/NO) |
| `pct_encrypted` | Decimal | Percentage of encrypted data |
| `reusedelay` | Integer | Reuse delay in days |