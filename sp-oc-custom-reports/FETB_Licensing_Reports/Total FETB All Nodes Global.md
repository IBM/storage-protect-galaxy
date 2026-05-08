# Total FETB (All Nodes / Global)

**Report ID:** R001

---

## 1. Overview

Get total front-end capacity across all nodes.

### Purpose

Provides a comprehensive view of the total Front-End Terabytes (FETB) capacity across all nodes in the system. This report helps in understanding the overall storage capacity being managed and is useful for licensing and capacity planning purposes.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | No input parameters required |

---

## 3. SQL Query

```sql
SELECT
    SUM(COALESCE(f.fecapacity, 0)) / 1024 / 1024 / 1024 AS total_fetb_gb
FROM FILESPACES f
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `total_fetb_gb` | Decimal | Total front-end capacity in gigabytes (GB) across all nodes |
