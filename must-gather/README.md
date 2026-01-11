# Must-Gather Scripts for IBM Storage Protect

## Introduction

The must-gather scripts are developed to collect diagnostic data across multiple products in the Storage Protect family. These can be found in their respective product-specific directories, as mentioned in the table below.


| **Product Name**            | **Name in the Scripts**                 |
|-----------------------------|-----------------------------|
| SP Server                   | sp-server                   |
| Storage Agent               | sp-server-sta               |
| SP Client – Backup-Archive  | sp-client-ba                |
| SP Client – Space Management| sp-client-space-mgmt        |
| SP Client – HSM for Windows | sp-client-hsm               |
| SP4VE – VMware              | sp-client-vmware            |
| SP4VE – Hyper-V             | sp-client-hyperv            |
| SP4DB – Oracle              | sp-client-oracle            |
| SP4DB – SQL                 | sp-client-sql               |
| SP4Mail – Exchange          | sp-client-exchange          |
| SP4Mail – Domino            | sp-client-domino            |
| SP4ERP – SAP HANA           | sp-client-erp-sap-hana      |
| SP4ERP – DB2                | sp-client-erp-db2           |
| SP4ERP – Oracle             | sp-client-erp-oracle        |


#### Each product directory contains its own script and a product-specific README that describes the modules applicable to that product.
#### Note: This is under development, and other product scripts will be added soon

## Prerequisites

### System Requirements

- Perl 5.x installed
- Sudo privileges for network/firewall commands (Linux/Aix/Solaris/MacOS)
-  IBM Storage Protect Product listed above must be installed on the system.
- Output directory must have write permissions


### Permissions

| OS | Requirement |
|----|-------------|
| Linux / AIX / Solaris / macOS | `sudo` required for firewall, tcpdump, and some system commands |
| Windows | Run script as Administrator|

## How to Run

### Basic Command

```bash
perl mustgather.pl --product <product_name> --output-dir <target_path> --adminid <id>  [options]
```
### Example

```bash
perl mustgather.pl --product sp-client-ba --output-dir /tmp/mustgather_output --adminid admin --verbose
```

### Mandatory Parameters

- `--product, -p` : Product name (`sp-client-ba`)  
- `--output-dir, -o` : Target folder for collected data
- `--adminid, -id` : Storage protect server admin ID

### Optional Parameters

- `--modules, -m` : Comma-separated list of modules to collect (default: all) 
- `--optfile` : Path to storage protect options file  
- `--no-compress` : Disable output compression  
- `--verbose, -v` : Print detailed logs  
- `--help, -h` : Display usage  


## Output Summary

At the end of execution, the script automatically creates a zip file:
```bash
mustgather_<product_name>_<timestamp>.zip
```
