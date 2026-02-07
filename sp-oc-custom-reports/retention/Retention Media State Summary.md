# Retention Media State Summary

**Report ID:** R025

---

## 1. Overview

Summarizes the number of retention volumes across different media states for each retention storage pool.

### Purpose

Monitor retention media health, validate offsite vaulting status, identify problematic volumes, and support DR readiness and retention compliance.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report analyzes current retention media state |

---

## 3. SQL Query

```sql 
SELECT
    COUNT(CASE WHEN state = 'MOUNTABLE'        THEN 1 END) AS MOUNTABLE,
    COUNT(CASE WHEN state = 'NOTMOUNTABLE'     THEN 1 END) AS NOTMOUNTABLE,
    COUNT(CASE WHEN state = 'COURIER'          THEN 1 END) AS COURIER,
    COUNT(CASE WHEN state = 'VAULT'            THEN 1 END) AS VAULT,
    COUNT(CASE WHEN state = 'VAULTRETRIEVE'    THEN 1 END) AS VAULTRETRIEVE,
    COUNT(CASE WHEN state = 'COURIERRETRIEVE'  THEN 1 END) AS COURIERRETRIEVE,
    COUNT(CASE WHEN state = 'ONSITERETRIEVE'   THEN 1 END) AS ONSITERETRIEVE,
    COUNT(CASE WHEN state = 'RESTOREONLY'      THEN 1 END) AS RESTOREONLY,
    COUNT(*) AS TOTALVOLUMES,
    stgpool_name
FROM
    retmedia
WHERE
    stgpool_name <> ''
    AND voltype = 'RETENTION'
GROUP BY
    stgpool_name;
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `MOUNTABLE` | Integer | Count of mountable volumes |
| `NOTMOUNTABLE` | Integer | Count of non-mountable volumes |
| `COURIER` | Integer | Volumes in courier state |
| `VAULT` | Integer | Volumes in vault state |
| `VAULTRETRIEVE` | Integer | Volumes pending vault retrieval |
| `COURIERRETRIEVE` | Integer | Volumes pending courier retrieval |
| `ONSITERETRIEVE` | Integer | Volumes pending onsite retrieval |
| `RESTOREONLY` | Integer | Volumes in restore-only state |
| `TOTALVOLUMES` | Integer | Total number of retention volumes |
| `stgpool_name` | String | Storage pool name |