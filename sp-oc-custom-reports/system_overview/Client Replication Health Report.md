# Client Replication Health Report

**Report ID:** R019

---

## 1. Overview

Provides a health overview of client replication status across servers.

### Purpose

Monitor replication delays and ensure DR readiness. Helps identify replication issues before they impact disaster recovery capabilities.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report queries current replication status |

---

## 3. SQL Query

```sql 
SELECT
    '%1$s' AS SERVER,
    NORMAL,
    WARNING,
    CRITICAL,
    COUNT
FROM
    (
        SELECT
            COUNT(status) AS NORMAL
        FROM
            TSMGUI_REPLCLI_GRID
        WHERE
            SERVER = '%1$s'
            AND STATUS = 0
            AND SYNCTIME > current_timestamp - 1 day
    ),
    (
        SELECT
            COUNT(status) AS WARNING
        FROM
            TSMGUI_REPLCLI_GRID
        WHERE
            SERVER = '%1$s'
            AND (
                (STATUS = 1 AND SYNCTIME > current_timestamp - 2 days)
                OR
                (STATUS = 0 AND SYNCTIME < current_timestamp - 1 day AND SYNCTIME > current_timestamp - 2 days)
            )
    ),
    (
        SELECT
            COUNT(status) AS CRITICAL
        FROM
            TSMGUI_REPLCLI_GRID
        WHERE
            SERVER = '%1$s'
            AND (
                STATUS = 2
                OR
                (STATUS = 1 AND SYNCTIME < current_timestamp - 2 days)
            )
    ),
    (
        SELECT
            COUNT(status) AS COUNT
        FROM
            TSMGUI_REPLCLI_GRID
        WHERE
            SERVER = '%1$s'
    );
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `SERVER` | String | Server name |
| `NORMAL` | Integer | Count of file spaces with normal replication status |
| `WARNING` | Integer | Count of file spaces with warning status |
| `CRITICAL` | Integer | Count of file spaces with critical status |
| `COUNT` | Integer | Total file spaces |