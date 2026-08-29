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
    cli.server,
    cli.name AS node_name,
    CASE
        WHEN TRIM(COALESCE(cli.vm_owner, '')) <> ''
            THEN owner.platform
        ELSE cli.platform
    END AS platform,
    CAST(
        SUM(COALESCE(cli.fe_capacity, 0)) * 1024
        AS DECIMAL(18, 2)
    ) AS fetb_gb
FROM
    tsmgui_allcli_grid cli
LEFT JOIN
    tsmgui_allcli_grid owner
        ON TRIM(owner.name) = TRIM(cli.vm_owner)
WHERE
    cli.has_fecap = 1
GROUP BY
    cli.server,
    cli.name,
    CASE
        WHEN TRIM(COALESCE(cli.vm_owner, '')) <> ''
            THEN owner.platform
        ELSE cli.platform
    END
ORDER BY
    cli.server,
    cli.name
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `server` | String | Name of the server |
| `node_name` | String | Name of the node |
| `platform` | String | Platform/operating system of the node |
| `fetb_gb` | Decimal | Front-end capacity in gigabytes (GB) for the node |
