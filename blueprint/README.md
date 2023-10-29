# Blueprints for Storage Protect offerings

A Blueprint consists of a document, or "cookbook", that describes the three reference architectures in detail, including IBM hardware model numbers and configuration requirements. It also includes scripts to speed up the installation and configuration, optimizing time-to-value. The storage preparation script automates preparation of the file systems that will be used by the Storage Protect offerings (IBM Storage Protect & IBM Storage Protect Plus). 

The [Blueprint configuration script]
* verify the hardware configuration and compares it with the Blueprint specifications
* validate kernel settings on the Operating systems, 
* verify the file-system configuration before installing the Storage Protect offering 
* create & configure IBM Db2 instance for IBM Storage Protect server
* define deduplication storage pools with optimal performance settings
* creates a dsmserv.opt file with best practice option overrides - for IBM Storage Protect
* define administrative maintenance tasks, optimized for data deduplication scalability
* configure the IBM Storage Protect database backup to disk
* create policy domains for database, mail, and file servers with management classes for 30, 60, and 120-day retention
* and so on.

**Supporting tools:**

The Blueprint documents leverage the [workload simulation tools](/tools/README.md) to generate synthetic load on the database and storage pool used by the Storage Protect offerings; in order to measure KPIs that can be used to compare as a reference against those measured on the Blueprint configuration.

## Blueprints for IBM Storage Protect (on premise)

**Blueprint docs:**
* [Blueprint for AIX](./storage-protect/docs/aix/Storage%20Protect%20Blueprint%20for%20AIX.md) **Coming Soon**
* [Blueprint for Linux](./storage-protect/docs/linux/Storage%20Protect%20Blueprint%20for%20Linux.md) **Coming Soon**
* [Blueprint for Linux on Power Systems](./storage-protect/docs/ppc-linux/Storage%20Protect%20Blueprint%20for%20Linux%20on%20Power%20Systems.md) **Coming Soon**
* [Blueprint for Windows](./storage-protect/docs/windows/Storage%20Protect%20Blueprint%20for%20Windows.md) 

**Scripts**
* Configuration script: [sp-config.pl](./storage-protect/sp-config/sp_config.pl)
* Cleanup script: [sp-cleanup.pl](./storage-protect/sp-config/sp_cleanup.pl)

## Blueprints for IBM Storage Protect (on Cloud)

**Blueprint docs:**
* [Cloud Blueprint for AWS](./storage-protect/docs/cloud/aws/Storage%20Protect%20Blueprint%20for%20Amazon%20Web%20Services.md) **Coming Soon**
* [Cloud Blueprint for Azure](./storage-protect/docs/cloud/azure/ Storage%20Protect%20Blueprint%20for%20Azure.md) **Coming Soon**
* [Cloud Blueprint for Google Cloud](./storage-protect/docs/cloud/google/Storage%20Protect%20Blueprint%20for%20Google%20Cloud.md) **Coming Soon**
* [Cloud Blueprint for IBM Cloud](./storage-protect/docs/cloud/ibm-cloud/Storage%20Protect%20Blueprint%20for%20IBM%20Cloud.md) **Coming Soon**

## Blueprint for IBM Storage Protect for Enterprise Resource Planning

**Blueprint docs:**
* [Blueprint for SAP HANA](./storage-protect/docs/sap-hana/Storage%20Protect%20Blueprint%20for%20SAP%20HANA.md)  **Coming Soon**

## Blueprint for Cyber Resiliency Solution for IBM Storage Scale (using IBM Storage Protect)

**Blueprint docs:**
* [ Cyber Resiliency Solution for IBM Storage Scale](./storage-protect/docs/spectrum-scale/Cyber%20Resiliency%20Solution%20for%20IBM%20Spectrum%20Scale.md) **Coming Soon**

## Blueprints for IBM Storage Protect Plus

**Blueprint docs:**
* [Blueprint for IBM Storage Protect Plus](./storage-protect-plus/docs/Spectrum%20Protect%20Plus%20Blueprint.md) **Coming Soon**
* [Blueprints and Sizing Spreadsheet for Storage Protect Plus](./storage-protect-plus/spp-config/resources/Storage%20Protect%20Plus%20Sizer%20v1.12.xlsb) **Coming Soon**

---
# Notices

Refer to [NOTICES](/NOTICES.md).

---