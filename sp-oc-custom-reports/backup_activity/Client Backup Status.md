# Client Backup Status

**Report ID:** R012

---

## 1. Overview

Provides a summary of client backup success and failure rates across servers for the last 24 hours.

### Purpose

Verify backup health and quickly identify servers with elevated failures. Helps prioritize troubleshooting efforts and monitor overall backup reliability.

---

## 2. Required Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| None | - | Defaults to last 24 hours |

---

## 3. SQL Query

```sql 
SELECT '%s' server,ROUND(FLOAT(f)*100/t,1) pct_failed,ROUND(FLOAT(s)*100/t,1) pct_success,t total,f total_failed,s total_success FROM(SELECT COUNT(*) t,SUM(CASE WHEN successful='NO' THEN 1 ELSE 0 END) f,SUM(CASE WHEN successful<>'NO' THEN 1 ELSE 0 END) s FROM(SELECT successful FROM summary WHERE activity IN('BACKUP','ARCHIVE') AND end_time>=CURRENT TIMESTAMP-24 HOURS UNION ALL SELECT successful FROM summary_extended WHERE activity='BACKUP' AND activity_type='SESSION_END' AND end_time>=CURRENT TIMESTAMP-24 HOURS UNION ALL SELECT successful FROM summary_extended WHERE activity='BACKUP' AND end_time>=CURRENT TIMESTAMP-24 HOURS AND(activity_type='Full' OR activity_type LIKE 'Incremental%') UNION ALL SELECT 'NO' FROM events WHERE scheduled_start>=CURRENT TIMESTAMP-24 HOURS AND status='Missed')x)a WHERE t>0
```

---

## 4. Output Details

| Output Field | Data Type | Description |
|--------------|-----------|-------------|
| `server` | String | Server name |
| `pct_failed` | Decimal | Percentage of failed backups |
| `pct_success` | Decimal | Percentage of successful backups |
| `total` | Integer | Total number of backup operations |
| `total_failed` | Integer | Number of failed backups |
| `total_success` | Integer | Number of successful backups |
