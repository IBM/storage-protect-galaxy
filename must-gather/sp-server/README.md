# Must-Gather Scripts for IBM Storage Protect Server

# sp-server
## Overview
These scripts collect system, network, configuration, server, replication, stgpool, and tape-related data for IBM Storage Protect servers.
They are designed to help IBM Support quickly diagnose issues by gathering all required server-side diagnostics in a consolidated package.

## Tested Platforms
- Linux (RHEL)
- Windows
- AIX


## Prerequisites
- Perl 5.x installed
- Sudo privileges for network/firewall commands (Linux/Aix)
- IBM Storage Protect Product must be installed on the system.
- Output directory must have write permissions


## How to Run
### Basic Command
```bash
perl mustgather.pl --product sp-server --output-dir <target_path> --adminid <id> [options]
perl mustgather.pl --product sp-server --output-dir <target_path> --adminid <id>  [options]
```

## Mandatory Parameters

- `--product, -p` : Product name (`sp-client-ba`)  
- `--output-dir, -o` : Target folder for collected data
- `--adminid, -id` : Storage protect server admin ID

## Optional Parameters

- `--modules, -m` : Comma-separated list of modules to collect (default: all) 
                 Example: --modules system,config,network
- `--optfile` : Path to storage protect options file  
- `--no-compress` : Disable output compression  
- `--verbose, -v` : Print detailed logs  
- `--help, -h` : Display usage  


## Example
```bash
perl mustgather.pl --product sp-server --output-dir /tmp/mustgather_output --adminid admin  --modules tape --verbose 
perl mustgather.pl --product sp-server --output-dir /tmp/mustgather_output --adminid admin  --modules tape --verbose 

```

## Data Collection Modules

- `system` : Collects system information, OS details, and environment variables.  

- `network` – Performs network tests including ping, port checks, firewall status, and interface info.

- `config` – Gathers Storage Protect server configuration files and environment settings.

- `server` – Runs Storage Protect administrative queries for system, storage, logs, and server status.

- `replication` – Collects replication configuration, rules, statuses, and backlog details.

- `stgpool` – Retrieves detailed storage pool information, statistics, and volume associations.

- `tape` – Collects tape library, drive, path definitions, volume information, and tape-related diagnostics.