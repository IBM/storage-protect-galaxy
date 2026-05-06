# Active vs Inactive FETB

**Report ID:** R004

---

## 1. Overview

Track usage trends, separate active vs inactive nodes.

### Purpose

Provides a summary of Front-End Terabytes (FETB) capacity categorized by node activity status. Nodes are classified as ACTIVE if accessed within the last 90 days, or INACTIVE otherwise. This report helps identify unused capacity, optimize licensing costs, and track usage trends over time.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Activity threshold is set to 90 days |

---

## 3. SQL Query

```sql
SELECT 
  CASE 
    WHEN DAYS(CURRENT DATE) - DAYS(n.lastacc_time) < 90 THEN 'ACTIVE'
    ELSE 'INACTIVE'
  END AS activity_status,
  SUM(COALESCE(f.fecapacity, 0)) / 1024 / 1024 / 1024 AS fetb_gb
FROM nodes n
JOIN filespaces f ON n.node_name = f.node_name
GROUP BY 
  CASE 
    WHEN DAYS(CURRENT DATE) - DAYS(n.lastacc_time) < 90 THEN 'ACTIVE'
    ELSE 'INACTIVE'
  END;
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `activity_status` | String | Node activity status: 'ACTIVE' (accessed within 90 days) or 'INACTIVE' (not accessed for 90+ days) |
| `fetb_gb` | Decimal | Total front-end capacity in gigabytes (GB) for the activity status |