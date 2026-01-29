#  Must-Gather Scripts for IBM Spectrum Protect for Virtual Environments - Data Protection for Hyper-V

# sp-client-hyperv
## Overview
These scripts collect system, network, configuration, logs, server, hyperv and performance data for IBM Spectrum Protect for Virtual Environments - Data Protection for Hyper-V.

## Tested Platforms
- Windows

## Prerequisites
- Perl 5.x installed
- IBM Storage Protect Product must be installed on the system.
- Output directory must have write permissions

## How to Run
### Basic Command
```bash
perl mustgather.pl --product sp-client-hyperv --output-dir <target_path> --adminid <id>  [options]
```

## Mandatory Parameters

- `--product, -p` : Product name (`sp-client-hyperv`)  
- `--output-dir, -o` : Target folder for collected data
- `--adminid, -id` : Storage protect server admin ID

## Optional Parameters

- `--modules, -m` : Comma-separated list of modules to collect (default: all) 
### Note : For sp-client-ba no need to provide --module parameter, it collect all by default 
- `--optfile` : Path to storage protect options file  
- `--no-compress` : Disable output compression  
- `--verbose, -v` : Print detailed logs  
- `--help, -h` : Display usage  


## Example
```bash
perl mustgather.pl --product sp-client-hyperv --output-dir /tmp/mustgather_output --adminid admin --verbose

```

## Data Collection Modules

- `system` : Collects system information, OS details, and environment variables. 

- `network` : Performs network checks including ping, port check, firewall rules, and tcpdump capture.

- `server`: Runs Storage Protect administrative queries for system, storage, logs, and server status.

- `config` : Collects IBM Storage Protect configuration files (`dsm.opt`, `dsm.sys`, `dsminfo.txt`, `query vm`).  

- `logs` : Gathers client logs such as `dsmj.log`, `dsminstr.log`, `dsmwebcl.log`, `dsmerror.log`, `dsmsched.log`. 

- `performance` : Captures performance metrics Instrumentation logs(`dsminstr.log`).

- `hyperv` :
Collects Hyper-V–specific diagnostics including:
Hyper-V PowerShell outputs (VMs, services, integration services)
VM inventory and VM file listings
Hyper-V cluster logs (if applicable)
VE framework, derby, and veProfile logs
Recovery Agent and mount operation logs
dsmc show vm output