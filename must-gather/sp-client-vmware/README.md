# Must-Gather Scripts for IBM Spectrum Protect for Virtual Environments – Data Protection for VMware

# sp-client-vmware
## Overview
These scripts collect system, network, configuration, logs, server, hyperv and performance data forIBM Spectrum Protect for Virtual Environments – Data Protection for VMware.

## Tested Platforms
- Windows
- Linux

## Prerequisites
- Perl 5.x installed
- IBM Storage Protect Product must be installed on the system.
- Output directory must have write permissions

## How to Run
### Basic Command
```bash
perl mustgather.pl --product sp-client-vmware --output-dir <target_path> --caseno <case_number> --adminid <id> [options]
```

## Mandatory Parameters

- `--product, -p` : Product name (`sp-client-vmware`)
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
perl mustgather.pl --product sp-client-vmware --output-dir /tmp/mustgather_output --caseno TS020757841 --adminid admin --verbose
```

## Data Collection Modules

- `system` : Collects system information, OS details, and environment variables. 

- `network` : Performs network checks including ping, port check, firewall rules, and tcpdump capture.

- `server`: Runs Storage Protect administrative queries for system, storage, logs, and server status.

- `config` : Collects IBM Storage Protect configuration files (`dsm.opt`, `dsm.sys`, `dsminfo.txt`, `query vm`).  

- `logs` : Gathers client logs such as `dsmj.log`, `dsminstr.log`, `dsmwebcl.log`, `dsmerror.log`, `dsmsched.log`. 

- `performance` : Captures performance metrics Instrumentation logs(`dsminstr.log`).

- `vmware` : Collects VMware-specific diagnostics for IBM Spectrum Protect Virtual Environments, including datamover information, VM inventory, Web GUI / FLR logs, Recovery Agent and mount operation logs, and vmcli configuration outputs across Windows and Linux platforms

## Output
The collected data will be saved in the specified output directory and compressed into a `.zip` file (unless `--no-compress` is used).