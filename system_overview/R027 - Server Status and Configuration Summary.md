# R027 -- Server Status and Configuration Summary

## 1. Overview

Provides a consolidated view of server version, retention, capacity, and
security settings.

## 2. Required Inputs

None.

## 3. Output Details

Server name, Version info, Capacity metrics, Retention policies,
Authentication and security settings.

## 4. SQL Query

```sql SELECT
    '--> Information from STATUS table' AS section_label,
    s.server_name,
    s.install_date,
    s.restart_date,
    s.platform,
    s.version,
    s.release,
    s.level,
    s.sublevel,
    s.actlogretention,
    s.actlogsize,
    s.summaryretention,
    s.eventretention,
    s.archretprot,
    s.machine_guid,
    s.server_lla,
    s.outbound_repl,
    s.totalsurocc_tb,
    s.surocc_date,
    s.totalsurretocc_tb,
    s.frontend_cap,
    s.frontend_client_count,
    s.frontend_cap_date,
    s.authentication,
    s.minpwlength,
    s.invalidpwlimit,
    s.passexp,
    s.command_approval,
    s.approver_reqapproval,
    (
        s.minpwalpha
        + s.minpwupper
        + s.minpwlower
        + s.minpwnum
        + s.minpwspec
        + s.pwreuselimit
    ) AS pw_strength
FROM
    status s,
    sysibm.sysdummy1 d;

```

## 5. Purpose for Customers

Helps customers quickly assess server configuration and compliance.
