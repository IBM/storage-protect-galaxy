# Must-Gather Scripts for IBM Spectrum Protect HSM Client

# sp-client-hsm
## Overview
These scripts collect system, network, configuration, logs, and HSM-specific diagnostic data for IBM Spectrum Protect HSM clients.

## Tested Platforms
- Linux 
- Windows

## Prerequisites
- Perl 5.x installed
- Sudo privileges for network/firewall commands (Linux/AIX/Solaris)
- IBM Spectrum Protect HSM Client must be installed on the system
- Output directory must have write permissions

## How to Run
### Basic Command
```bash
perl mustgather.pl --product sp-client-hsm --output-dir <target_path> --adminid <id> --caseno <case_number> [options]
```

## Mandatory Parameters

- `--product, -p` : Product name (`sp-client-hsm`)
- `--output-dir, -o` : Target folder for collected data
- `--adminid, -id` : Storage Protect server admin ID (password prompted securely)
- `--caseno, -c` : IBM Support Case Number (format: TS followed by 9 digits, e.g., TS020757841)

## Optional Parameters

- `--modules, -m` : Comma-separated list of modules to collect (default: all)
- `--optfile` : Path to Storage Protect options file
- `--no-compress` : Disable output compression
- `--verbose, -v` : Print detailed logs
- `--help, -h` : Display usage

## Example
```bash
perl mustgather.pl --product sp-client-hsm --output-dir /tmp/mustgather_output --adminid admin --caseno TS020757841 --verbose
```

## Data Collection Modules

- `system` : Collects system information, OS details, and environment variables.

- `network` : Performs network checks including ping, port check, firewall rules, and tcpdump capture.

- `server` : Runs Storage Protect administrative queries for system, storage, logs, and server status.

- `config` : Collects IBM Storage Protect configuration files (`dsm.opt`, `dsm.sys`, `dsminfo.txt`).

- `logs` : Gathers client logs such as `dsmj.log`, `dsminstr.log`, `dsmwebcl.log`, `dsmerror.log`, `dsmsched.log`.

- `hsm` : Collects HSM-specific data including:
  - HSM system information (dsmc query systeminfo with HSM optfile)
  - **Windows-specific commands:**
    - dsminfo.exe all (complete HSM information)
    - dsmhsmclc.exe -query (HSM client configuration)
    - dsmhsmclc.exe check (HSM client status check)
    - dsmclc.exe listfilespaces (HSM file spaces)
  - **Unix/Linux-specific commands:**
    - dsmmigfs queries (file system migration details)
    - dsmdf (disk space information)
    - dsmmigquery (HSM options and management)
    - SpaceMan configuration directory listing
  - HSM service/process status (OS-specific)
  - HSM registry information (Windows only)

