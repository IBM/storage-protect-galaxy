#  Must-Gather Scripts for IBM Spectrum Protect for Databases - SQL 
# sp-client-sql
## Overview
These scripts collect system, network, configuration, logs, server, sql  and performance data for IBM Spectrum Protect for Virtual Environments - Data Protection for Databases - SQL.

## Tested Platforms
- Windows

## Prerequisites
- Perl 5.x installed
- IBM Storage Protect Product must be installed on the system.
- Output directory must have write permissions

## How to Run
### Basic Command
```bash
perl mustgather.pl --product sp-client-sql --output-dir <target_path> -caseno <caseno> --adminid <adminid> --verbose    
```

## Mandatory Parameters

- `--product, -p` : Product name (`sp-client-sql`)
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
perl mustgather.pl --product sp-client-sql --output-dir /tmp/mustgather_output --adminid admin -caseno TS738982982 --verbose

```

## Data Collection Modules

- `system` : Collects system information, OS details, and environment variables. 

- `network` : Performs network checks including ping, port check, firewall rules, and tcpdump capture.

- `server`: Runs Storage Protect administrative queries for system, storage, logs, and server status.

- `config` : Collects IBM Storage Protect configuration files (`dsm.opt`, `dsm.sys`, `dsminfo.txt`, `query vm`).  

- `logs` : Gathers client logs such as `dsmj.log`, `dsminstr.log`, `dsmwebcl.log`, `dsmerror.log`, `dsmsched.log`. 

- `performance` : Captures performance metrics Instrumentation logs(`dsminstr.log`).

- `sql` : Collects Data Protection for SQL configuration, logs, version details, registry data, and TDPSQL query outputs.
