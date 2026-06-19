# Must-Gather for IBM Spectrum Protect API for DB2

## Overview

This must-gather script collects diagnostic data for IBM Spectrum Protect DB2 client backup using the API. It gathers configuration files, logs, DB2 client information, and platform-specific data required for troubleshooting.

## Prerequisites

- IBM Spectrum Protect API Client must be installed
- DB2 client must be installed
- Perl 5.x or higher
- Appropriate permissions to read configuration files and logs
- For network/firewall commands: sudo privileges (Linux/AIX/Solaris/macOS) 

## How to Run
### Basic Command
```bash
perl mustgather.pl --product sp-client-api-db2 --output-dir <target_path> -caseno <caseno> --adminid <adminid> --verbose    
``

## Mandatory Parameters

- `--product, -p` : Product name (`sp-client-exchange`)
- `--output-dir, -o` : Target folder for collected data
- `--caseno, -c` : IBM Support Case Number (format: TS followed by 9 digits, e.g., TS020757841)
- `--adminid, -id` : Storage Protect server admin ID (password will be prompted securely)

## Optional Parameters

- `--modules, -m` : Comma-separated list of modules to collect (default: all)
- `--optfile` : Path to storage protect options file
- `--no-compress` : Disable output compression  
- `--verbose, -v` : Print detailed logs  
- `--help, -h` : Display usage  


## Example
```bash
perl mustgather.pl --product sp-client-exchange --output-dir /tmp/mustgather_output --caseno TS020757841 --adminid admin --verbose
```

## Data Collection Modules

- `system` : Collects system information, OS details, and environment variables. 

- `network` : Performs network checks including ping, port check, firewall rules, and tcpdump capture.

- `server`: Runs Storage Protect administrative queries for system, storage, logs, and server status.

- `config` : Collects IBM Storage Protect configuration files (`dsm.opt`, `dsm.sys`, `dsminfo.txt`, `query vm`).  

- `logs` : Gathers client logs such as `dsmj.log`, `dsminstr.log`, `dsmwebcl.log`, `dsmerror.log`, `dsmsched.log`. 

- `performance` : Captures performance metrics Instrumentation logs(`dsminstr.log`).

- `apidb2` :Collects API client configuration and logs (dsm.opt, dsm.sys, dsierror.log), DB2 diagnostics (db2diag.log, db2level),db2 configuration (db2 get db cfg), environment variables, and platform-specific details.

## Output
The collected data will be saved in the specified output directory and compressed into a `.zip` file (unless `--no-compress` is used).