# Server Status and Configuration Summary

**Report ID:** R027

---

## 1. Overview

Provides a consolidated view of server version, retention, capacity, and security settings.

### Purpose

Quickly assess server configuration and compliance. Helps validate security policies, retention settings, and overall server health.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Report queries current server configuration |

---

## 3. SQL Query

```sql 
SELECT
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

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `section_label` | String | Section identifier |
| `server_name` | String | Server name |
| `install_date` | Date | Installation date |
| `restart_date` | Timestamp | Last restart date/time |
| `platform` | String | Server platform |
| `version` | Integer | Version number |
| `release` | Integer | Release number |
| `level` | Integer | Level number |
| `sublevel` | Integer | Sublevel number |
| `actlogretention` | Integer | Activity log retention (days) |
| `actlogsize` | Integer | Activity log size (MB) |
| `summaryretention` | Integer | Summary retention (days) |
| `eventretention` | Integer | Event retention (days) |
| `archretprot` | String | Archive retention protection status |
| `machine_guid` | String | Machine GUID |
| `server_lla` | String | Server last login address |
| `outbound_repl` | String | Outbound replication status |
| `totalsurocc_tb` | Decimal | Total storage occupancy (TB) |
| `surocc_date` | Date | Storage occupancy date |
| `totalsurretocc_tb` | Decimal | Total retention occupancy (TB) |
| `frontend_cap` | Decimal | Frontend capacity |
| `frontend_client_count` | Integer | Frontend client count |
| `frontend_cap_date` | Date | Frontend capacity date |
| `authentication` | String | Authentication method |
| `minpwlength` | Integer | Minimum password length |
| `invalidpwlimit` | Integer | Invalid password attempt limit |
| `passexp` | Integer | Password expiration (days) |
| `command_approval` | String | Command approval requirement |
| `approver_reqapproval` | String | Approver requires approval |
| `pw_strength` | Integer | Calculated password strength score |