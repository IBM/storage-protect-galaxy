# Highest Rate of Backup Failure in VM Clients

**Report ID:** R014

---

## 1. Overview

Identifies VMs with the highest backup failure percentages.

### Purpose

Detect unstable VM backups and hypervisor issues. Shows the top 10 VMs with the worst backup success rates to prioritize troubleshooting VM-specific backup problems.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report analyzes all VM backup history |

---

## 3. SQL Query

```sql 
SELECT
    node_name,
    clients.type,
    rate,
    fail_table.server
FROM (
    SELECT
        a.node_name,
        a.as_entity,
        ROUND(CAST(failed AS FLOAT) / total_vm * 100.0, 1) AS rate,
        '%s' AS server
    FROM (
        SELECT
            name AS node_name,
            as_entity,
            COUNT(name) AS failed
        FROM
            summary_extended s
        INNER JOIN
            tsmgui_allcli_grid
                ON sub_entity = name
                AND as_entity = vm_owner
        WHERE
            activity = 'BACKUP'
            AND status > 0
            AND successful = 'NO'
            AND (
                activity_type = 'Full'
                OR activity_type LIKE 'Incremental%'
            )
            AND sub_entity IS NOT NULL
        GROUP BY
            name,
            as_entity
    ) a
    INNER JOIN (
        SELECT
            name AS node_name,
            as_entity,
            COUNT(name) AS total_vm
        FROM
            summary_extended s
        INNER JOIN
            tsmgui_allcli_grid
                ON sub_entity = name
                AND as_entity = vm_owner
        WHERE
            activity = 'BACKUP'
            AND (
                activity_type = 'Full'
                OR activity_type LIKE 'Incremental%'
            )
            AND sub_entity IS NOT NULL
        GROUP BY
            name,
            as_entity
    ) b
        ON a.node_name = b.node_name
        AND a.as_entity = b.as_entity
) fail_table
INNER JOIN
    tsmgui_allcli_grid clients
        ON fail_table.node_name = clients.name
        AND fail_table.as_entity = clients.vm_owner
        AND fail_table.server = clients.server
ORDER BY
    rate DESC
FETCH FIRST
    10 ROWS ONLY;
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `node_name` | String | VM name |
| `type` | String | Client type |
| `rate` | Decimal | Backup failure rate percentage |
| `server` | String | Storage Protect server name |