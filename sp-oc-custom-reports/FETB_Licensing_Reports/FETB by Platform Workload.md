# FETB by Platform / Workload

**Report ID:** R003

---

## 1. Overview

Measure FETB per platform and OS for reporting and audits.

### Purpose

Provides an aggregated view of Front-End Terabytes (FETB) capacity grouped by platform and operating system. This report is valuable for understanding capacity distribution across different platforms, supporting audit requirements, and making platform-specific licensing decisions.

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

    COALESCE(
        NULLIF(NULLIF(TRIM(cli.platform), ''), '?'),
        NULLIF(NULLIF(TRIM(owner.platform), ''), '?')
    ) AS platform,

    CAST(
        SUM(COALESCE(cli.fe_capacity, 0)) AS DECIMAL(12, 2)
    ) * 1024 AS femb_gb

FROM
    tsmgui_allcli_grid cli

LEFT JOIN
    tsmgui_allcli_grid owner
        ON TRIM(owner.name) = TRIM(cli.vm_owner)

WHERE
    cli.has_fecap = 1

GROUP BY
    cli.server,
    COALESCE(
        NULLIF(NULLIF(TRIM(cli.platform), ''), '?'),
        NULLIF(NULLIF(TRIM(owner.platform), ''), '?')
    )

ORDER BY
    cli.server
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `server` | String | Operating system name of the clients |
| `platform` | String | Platform type of the nodes |
| `fetb_gb` | Decimal | Total front-end capacity in gigabytes (GB) for the platform/OS combination |
