#  Must-Gather Scripts for IBM Spectrum Protect for Enterprise Resource Planning - Data Protection for SAP® for DB2
# sp-client-sap-db2
## Overview
These scripts collect system, network, configuration, logs, server, sql  and performance data forIBM Spectrum Protect for Enterprise Resource Planning - Data Protection for SAP® for DB2.

## Tested Platforms
- Windows

## Prerequisites
- Perl 5.x installed
- IBM Storage Protect Product must be installed on the system.
- Output directory must have write permissions

## How to Run
### Basic Command
```bash
perl mustgather.pl --product sp-client-sap-db2 --output-dir <target_path> -caseno <caseno> --adminid <adminid> --verbose    
```

## Mandatory Parameters

- `--product, -p` : Product name (`sp-client-sap-db2`)
- `--output-dir, -o` : Target folder for collected data
- `--caseno, -c` : IBM Support Case Number (format: TS followed by 9 digits, e.g., TS020757841)
- `--adminid, -id` : Storage Protect server admin ID (password will be prompted securely)


## Optional Parameters

- `--modules, -m` : Comma-separated list of modules to collect (default: all) 
### Note : For sp-client-ba no need to provide --module parameter, it collect all by default 
- `--optfile` : Path to storage protect options file  
- `--no-compress` : Disable output compression  
- `--verbose, -v` : Print detailed logs  
- `--help, -h` : Display usage  


## Example
```bash
perl mustgather.pl --product sp-client-sap-db2 --output-dir /tmp/mustgather_output --adminid admin -caseno TS738982982 --verbose

```

## Data Collection Modules

- `system` : Collects system information, OS details, and environment variables. 

- `network` : Performs network checks including ping, port check, firewall rules, and tcpdump capture.

- `server`: Runs Storage Protect administrative queries for system, storage, logs, and server status.

- `config` : Collects IBM Storage Protect configuration files (`dsm.opt`, `dsm.sys`, `dsminfo.txt`, `query vm`).  

- `logs` : Gathers client logs such as `dsmj.log`, `dsminstr.log`, `dsmwebcl.log`, `dsmerror.log`, `dsmsched.log`. 

- `performance` : Captures performance metrics Instrumentation logs(`dsminstr.log`).

- `Sap-db2` : Collects SAP-specific configuration files (init*.sap, init*.utl), DB2 database configurations, API client settings (dsm.sys/dsm.opt from API directories), and diagnostic logs including db2diag.log and TDP DB2 logs.
  This module provides comprehensive data for troubleshooting SAP DB2 backup and recovery issues with IBM Storage Protect.
