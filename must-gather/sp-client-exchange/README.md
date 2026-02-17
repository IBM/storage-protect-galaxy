#  Must-Gather Scripts for IBM Storage Protect for Mail – Data Protection for Microsoft Exchange

# sp-client-exchange
## Overview
These scripts collect system, network, configuration, logs, server, Exchange, and performance data for IBM Storage Protect for Mail – Data Protection for Microsoft Exchange Server environments.

## Tested Platforms
- Windows

## Prerequisites
- Perl 5.x installed
- IBM Storage Protect Product must be installed on the system.
- Output directory must have write permissions

## How to Run
### Basic Command
```bash
perl mustgather.pl --product sp-client-exchange --output-dir <target_path> --caseno <case_number> --adminid <id> [options]
```

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

- `exchange` :Collects dsm.opt, relevant client logs (dsmerror.log, dsminstr.log, dsmsched.log), Windows version details, and Spectrum Protect Client version.
Also gathers tdpexc.log, tdpexc.cfg, and outputs of TDPEXCC QUERY TSM, QUERY EXCHANGE, and QUERY TDP.

## Output
The collected data will be saved in the specified output directory and compressed into a `.zip` file (unless `--no-compress` is used).