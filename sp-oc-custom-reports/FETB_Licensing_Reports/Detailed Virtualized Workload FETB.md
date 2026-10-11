
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
SELECT
    cli.server,

    COALESCE(
        NULLIF(NULLIF(TRIM(cli.platform), ''), '?'),
        NULLIF(NULLIF(TRIM(owner.platform), ''), '?'),
        'UNKNOWN'
    ) AS platform,

    CASE
        WHEN cli.vm_type = 2 THEN 'TRUE'
        ELSE ''
    END AS hypervisor,

    CASE
        WHEN cli.vm_type = 1 THEN 'TRUE'
        ELSE ''
    END AS sp4ve,

    CAST(
        SUM(cli.fe_capacity) AS DECIMAL(12, 2)
    ) AS fe_mb

FROM
    tsmgui_allcli_grid cli

LEFT JOIN
    tsmgui_allcli_grid owner
        ON TRIM(owner.name) = TRIM(cli.vm_owner)

WHERE
    cli.has_fecap = 1
    AND cli.fe_capacity > 0

GROUP BY
    cli.server,
    COALESCE(
        NULLIF(NULLIF(TRIM(cli.platform), ''), '?'),
        NULLIF(NULLIF(TRIM(owner.platform), ''), '?'),
        'UNKNOWN'
    ),
    cli.vm_type

ORDER BY
    cli.server,
    platform
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `platform` | String | Platform type of the nodes |
| `hypervisor` | String | Hypervisor type for virtualized workloads |
| `sp4ve` | String | SP4VE flag: 'TRUE' if protected by Storage Protect for Virtual Environments, empty otherwise |
| `fe_mb` | Decimal | Total front-end capacity in megabytes (MB) for the combination |
