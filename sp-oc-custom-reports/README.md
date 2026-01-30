# 📊 IBM Storage Protect – Report Repository

## 📘 About This Repository
This repository provides a centralized collection of IBM Storage Protect custom reports. Each report is stored as an individual Markdown file inside a category folder and can be accessed using the links below.

## How to Use These Reports in Storage Protect OC

These reports can be configured and executed from the **Storage Protect Operations Center (SP OC)** user interface:

1. **Import Report Templates**: Navigate to the Reports section in SP OC and import the desired report template from this repository.
2. **Configure Parameters**: Provide the required input parameters specific to each report (e.g., time ranges, node names, thresholds).
3. **Execute Reports**: Run the report to generate real-time insights related to storage usage, performance, capacity, and system health.
4. **Schedule & Export**: Schedule recurring report execution or export results for further analysis and documentation.

The SP OC interface provides an intuitive way to manage, customize, and visualize these reports for operational and capacity planning purposes.

---

## 🗄️ Storage Utilization  
*Reports that show how storage capacity is allocated, used, and consumed across the environment.*

| Report | Tags |
|--------|------|
| [Storage Pool Utilization](storage_utilization/Storage%20Pool%20Utilization.md) | `Usage`, `Capacity`, `Performance` |
| [Storage Pool Savings Summary](storage_utilization/Storage%20Pool%20Savings%20Summary.md) | `Usage`, `Capacity` |
| [Storage Utilization Summary](storage_utilization/Storage%20Utilization%20Summary.md) | `Usage`, `Capacity` |
| [Storage Pool Capacity and Utilization Summary](storage_utilization/Storage%20Pool%20Capacity%20and%20Utilization%20Summary.md) | `Usage`, `Capacity` |
| [Node Storage Consumption Summary](storage_utilization/Node%20Storage%20Consumption%20Summary.md) | `Usage`, `Capacity` |
| [Large Data Movement Summary](storage_utilization/Large%20Data%20Movement%20Summary.md) | `Usage`, `Performance` |

---

## 📉 Storage Savings (Compression & Deduplication)  
*Reports that analyze how efficiently data is reduced using compression and deduplication.*

| Report | Tags |
|--------|------|
| [Node with the Best Overall Savings](storage_savings/Node%20with%20the%20Best%20Overall%20Savings.md) | `Top10`, `Usage`, `Performance` |
| [Top 10 Best Compressed Nodes](storage_savings/Top%2010%20Best%20Compressed%20Nodes.md) | `Top10`, `Usage`, `Performance` |
| [Top 10 Least Compressed Nodes](storage_savings/Top%2010%20Least%20Compressed%20Nodes.md) | `Bottom10`, `Usage`, `Performance` |
| [Top 10 Deduplicated Nodes](storage_savings/Top%2010%20Deduplicated%20Nodes.md) | `Top10`, `Usage`, `Performance` |
| [Worst Deduplicated Nodes](storage_savings/Worst%20Deduplicated%20Nodes.md) | `Bottom10`, `Usage`, `Performance` |
| [Lowest Compression Rate](storage_savings/Lowest%20Compression%20Rate.md) | `Bottom10`, `Usage`, `Performance` |
| [Lowest Deduplication Rate](storage_savings/Lowest%20Deduplication%20Rate.md) | `Bottom10`, `Usage`, `Performance` |
| [Data Reduction Efficiency](storage_savings/Data%20Reduction%20Efficiency.md) | `Usage`, `Performance` |
| [Daily Data Reduction](storage_savings/Daily%20Data%20Reduction.md) | `Usage`, `Performance` |

---

## 🧪 Backup Activity & Health  
*Reports that monitor backup operations, failures, and data ingestion trends.*

| Report | Tags |
|--------|------|
| [Node Backups in the Last N Hours](backup_activity/Node%20Backups%20in%20the%20Last%20N%20Hours.md) | `Health`, `Performance` |
| [Summarized Node Backups in the Last N Hours](backup_activity/Summarized%20Node%20Backups%20in%20the%20Last%20N%20Hours.md) | `Health`, `Performance` |
| [Daily Ingest](backup_activity/Daily%20Ingest.md) | `Usage`, `Performance` |
| [Client Backup Status](backup_activity/Client%20Backup%20Status.md) | `Health`, `Performance` |
| [Highest Rate of Backup Failure](backup_activity/Highest%20Rate%20of%20Backup%20Failure.md) | `Top10`, `Health` |
| [Highest Rate of Backup Failure in VM Clients](backup_activity/Highest%20Rate%20of%20Backup%20Failure%20in%20VM%20Clients.md) | `Top10`, `Health` |
| [Summary of Most Data Backed Up](backup_activity/Summary%20of%20Most%20Data%20Backed%20Up.md) | `Top10`, `Usage`, `Performance` |
| [Top 10 Clients with Largest Number of File Backups](backup_activity/Top%2010%20Clients%20with%20Largest%20Number%20of%20File%20Backups.md) | `Top10`, `Usage` |
| [Summary of Daily Data Ingest](backup_activity/Summary%20of%20Daily%20Data%20Ingest.md) | `Usage`, `Performance` |

---

## 🗂️ Retention & Data Lifecycle  
*Reports related to retention policies, expiring data, and cleanup activities.*

| Report | Tags |
|--------|------|
| [Retention Hold Activity](retention/Retention%20Hold%20Activity.md) | `Health`, `Usage` |
| [Expiring Retention Sets](retention/Expiring%20Retention%20Sets.md) | `Health`, `Capacity` |
| [Deleted Retention Sets](retention/Deleted%20Retention%20Sets.md) | `Health`, `Usage` |
| [Retention Media State Summary](retention/Retention%20Media%20State%20Summary.md) | `Health`, `Capacity` |

---

## 🗄️ Database Monitoring & Health  
*Reports that track database space usage, security, and layout.*

| Report | Tags |
|--------|------|
| [Database Space and Page Utilization Summary](database/Database%20Space%20and%20Page%20Utilization%20Summary.md) | `Health`, `Capacity` |
| [Database Protect Master Key Status](database/Database%20Protect%20Master%20Key%20Status.md) | `Health` |
| [Database Space Location Summary](database/Database%20Space%20Location%20Summary.md) | `Health`, `Capacity` |
| [Database Space Path Breakdown](database/Database%20Space%20Path%20Breakdown.md) | `Health`, `Capacity` |

---

## ☁️ Cloud & Object Store  
*Reports related to cloud tiering, container usage, and cloud pool monitoring.*

| Report | Tags |
|--------|------|
| [Cloud Container Cleanup Status Report](cloud_object_store/Cloud%20Container%20Cleanup%20Status%20Report.md) | `Health`, `Usage` |
| [Cloud Pool Usage Summary](cloud_object_store/Cloud%20Pool%20Usage%20Summary.md) | `Usage`, `Capacity` |

---

## 🔄 Replication, Chargeback & System Overview  
*High-level reports for replication status, chargeback, and overall system health.*

| Report | Tags |
|--------|------|
| [Client Replication Health Report](system_overview/Client%20Replication%20Health%20Report.md) | `Health`, `Performance` |
| [Charge Back Capacity](system_overview/Charge%20Back%20Capacity.md) | `Capacity`, `Usage` |
| [Server Status and Configuration Summary](system_overview/Server%20Status%20and%20Configuration%20Summary.md) | `Health`, `Performance` |

---

## 🏷️ Tag Reference

Use these tags to quickly find reports by characteristic:

- **`Usage`** - Reports focused on storage consumption and data usage patterns
- **`Performance`** - Reports analyzing system and operational performance metrics
- **`Capacity`** - Reports related to storage capacity planning and availability
- **`Health`** - Reports monitoring system health, failures, and operational status
- **`Top10`** - Reports showing top performers or highest values
- **`Bottom10`** - Reports showing lowest performers or areas needing attention
