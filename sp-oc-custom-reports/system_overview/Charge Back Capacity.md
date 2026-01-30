# Charge Back Capacity

**Report ID:** R020

---

## 1. Overview

Provides server-level capacity metrics for internal cost allocation and charge-back.

### Purpose

Support cost allocation and capacity charge-back models. Enables financial tracking and departmental billing based on storage consumption.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report queries current server capacity metrics |

---

## 3. SQL Query

```sql  
SELECT
    NAME,
    VRMF,
    STATUS,
    NUMCLIENTS,
    FE_NUMCLIENTS,
    NUMCLIENTS - FE_NUMCLIENTS AS FE_NUMCLIENTS_NOTREPORTED,
    FE_CAPACITY_TB,
    FE_TIMESTAMP,
    SUR_OCC AS BE_CAPACITY_TB,
    SUR_RET_OCC AS RET_CAPACITY_TB,
    SUROCC_TIMESTAMP AS BE_TIMESTAMP
FROM
    TSMGUI_ALLSRV_GRID
WHERE
    CONFIGURED > 0
ORDER BY
    STATUS;
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `NAME` | String | Server name |
| `VRMF` | String | Version/Release/Modification/Fix level |
| `STATUS` | String | Server status |
| `NUMCLIENTS` | Integer | Total number of clients |
| `FE_NUMCLIENTS` | Integer | Frontend clients reported |
| `FE_NUMCLIENTS_NOTREPORTED` | Integer | Frontend clients not reported |
| `FE_CAPACITY_TB` | Decimal | Frontend capacity (TB) |
| `FE_TIMESTAMP` | Timestamp | Frontend capacity timestamp |
| `BE_CAPACITY_TB` | Decimal | Backend capacity (TB) |
| `RET_CAPACITY_TB` | Decimal | Retention capacity (TB) |
| `BE_TIMESTAMP` | Timestamp | Backend capacity timestamp |