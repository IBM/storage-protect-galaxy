# Storage Protect Blueprint - toolkit

The IBM Storage Protect blueprints provide documentation and tools to configure extra-small, small, medium, and large - IBM Storage Protect server architectures.  It includes a collection of tools to prepare, deploy, configure, and tear-down a Storage Protect Blueprint.

---
## Prepare

The storage preparation tool is used to prepare the LVM components / file-systems used by the IBM Storage Protect server (for the blueprint).

| OS  | Script |
|-----|--------|
| Microsoft Windows 2016 or 2019 | `storage_prep_win.pl` |
| Linux x86_64 and Linux on Power | `storage_prep_lnx.pl` |
| AIX | `storage_prep_aix.pl` |

By default, this script will attempt to determine which disks to use for different volume groups based on the disk size.

Use the `-uselist` option to modify the disk lists, if your disk layout differs from the blueprint specifications.

---
## Configure

The tool (`sp_config.pl`) is used to install & configure a IBM Storage Protect server on AIX, Linux x86, Linux on Power, or Windows.  The tool verifies that the hardware configuration meets the Blueprint specifications, validates kernel settings, and verifies the configuration of required file systems prior to running the standard IBM Storage Protect server installation. The script also configures the IBM Storage Protect server using best practices and:

* Creates an IBM DB2 instance
* Defines deduplication storage pools with optimal performance settings
* Defines administrative maintenance tasks optimized for data deduplication scalability
* Defines IBM Storage Protect database backup to disk
* Creates a dsmserv.opt file with best practice option overrides
* Creates policy domains for database, mail, and file servers with management classes for 30, 60, and 120-day retention
* For all client types, defines backup schedules that can be selected when deploying the desired client workloads

---
## Cleanup

> CAUTION: This tool is destructive, and will completely remove your Storage Protect server and all stored data. 

You can use this tool to completely cleanup and remove a Storage Protect server that was configured using the `Storage Protect Blueprint configuration` tool.  The `sp_cleanup.pl` script is an implementation of the `Storage Protect Blueprint cleanup` tool. This is a destructive tool and should only be used for troubleshooting purposes during initial testing of the blueprint script.  

This tool uses the `serversetupstatefileforcleanup.txt` file that was previoudly generated by the `Storage Protect Blueprint configuration` tool.  The `sp_config.pl` script is an implementation of the `Storage Protect Blueprint configuration` tool.

### Usage
To use this tool:

1. Copy `sp_cleanup.pl` into the same folder where `sp_config.pl` is located
1. Edit `sp_cleanup.pl` file to comment-out the `exit` statement, on the first line
1. Run `perl sp_cleanup.pl`

---
