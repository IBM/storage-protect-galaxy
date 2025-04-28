# Consistent SGC for IBM Storage Protect on IBM Storage Scale

-------------------------


## Introduction

This project provides scripts (Unix bash) that facilitate the creation and restoration of consistent safeguarded copies (SGC) for IBM Storage Protect server instance storing their data in IBM Storage Scale file systems. These scripts use the Storage Scale CLI or REST API to manage snapshots. 

The terms safeguarded copy (SGC) and immutable snapshots are used interchangibly. 

Multiple IBM Storage Protect server instance can share the same set of file systems provided by IBM Storage Scale. Each Storage Protect instance uses its own independent fileset in each file system to store data and metadata. This allows to create consistent and immutable snapshots for a particular Storage Protect instance in the relevant file systems and filesets. More importantly it allows fast restore of snapshots for a particular instance. 


Find below a description of the prerequisites, installation and configuration and workflows and scripts.  


### Requirements and Limitations

Find below some limitations for the usage of these scripts with IBM Storage Scale:

- Storage Scale version 5.1.9, 5.2.1 and 5.2.2 were tested on RHEL 8 and RHEL 9
- Storage Scale ESS and Storage Scale software defined deployments were tested
- Single cluster and remote cluster architectures (Storage Protect instances running in remote cluster) were tested
- Stretched cluster was tested
- Each instance must either have dedicated filesystem or dedicated independent fileset for all instance specific backup data and metadata
- Storage Protect version 8.1.25 and above were tested
- Storage Protect disk, file and container pools were tested
- Volume reuse delay for Storage Protect volumes must be set to the retention period of the snapshots plus 1
- JSON parser program `jq` is required


### License

This project is under [Apache License 2.0](../../LICENSE).

------------------------------

## Prerequisites

This section describes the configuration model of the Storage Scale file systems and filesets used by the Storage Protect instance.


### File system configuration

The script for creating and restoring consistent and immutable Storage Protect instance snapshots requires that each Storage Protect instance stores its data and metadate in a Storage Scale independent fileset of each relevant file system. An independent fileset allow taking snapshots just for the fileset and not the entire file system. More importantly, it allows to restore an individual fileset in a file system. Restoring the entire file system (instead of the fileset) restores the data for all instances using the file system. This is not desirable because the restored snapshot must have been created while the Storage Protect instance was suspended. 

Here is an example of a file system and fileset configuration for two Storage Protect instances. It does not matter if these two instances run on the same server or not. 

| File system purpose | File system mount point | Fileset path for Instance 1 | Fileset path for instance 2|
|---------------------|-------------------------|-----------------------------|-----------------------------|
| TSM DB | /gpfs/tsmdb | /gpfs/tsmdb/inst01 | /gpfs/tsmdb/inst02 |
| Active logs | /gpfs/tsmlog | /gpfs/tsmlog/inst01 | /gpfs/tsmlog/inst02 |
| Archive logs | /gpfs/tsmalog | /gpfs/tsmalog/inst01 | /gpfs/tsmalog/inst02 |
| DB backup | /gpfs/tsmbackup | /gpfs/tsmbackup/inst01 | /gpfs/tsmbackup/inst02 |
| Storage pools | /gpfs/tsmstg | /gpfs/tsmstg/inst01  | /gpfs/tsmstg/inst02 |
| Instance | /gpfs/tsminst | /gpfs/tsminst/inst01 | /gpfs/tsminst/inst02 |

As shown in the table above, each instance has its own independent filesets in the file system. For example, instance 1 has the filesets created in the subdirectory inst01 of each file system. 

Without independent filesets for each instance, the workflows presented below do not work!!

**Note:** If there are nested independent filesets within the independent fileset to be snapped, then these nested independent are not included in the snapshot. Therefore, it is not supported to use nested independent fileset. 

**Note:** If there are nested dependent filesets within the independent fileset to be snapped, then these nested dependent are not restored. The files of the dependent fileset are included in the snapshot and can be restored by copying the files from the snapshot into the dependent fileset directory. Therefore, it is not recommended to use nested dependent filesets.  


------------------------------

## Installation and configuration

This section describes the installation and configuration of the scripts associated with this project. 


### Copy and explore scripts

Copy or git clone the scripts to the Storage Protect server (e.g. `/usr/local/bin`) and make the script files `*.sh` executable:

```
# git clone https://github.com/IBM/storage-protect-galaxy.git ./
# cd snap-protect/
# chmod +x storage-scale/*.sh
```

**Note:** The gitHub repository is only accessible by the IBM organization. If you obtained the scripts from IBM, then copy the scripts to the Storage Protect servers. 

The following files are included in this project:

```
./
├── isnap-del.sh
├── isnap-fscap.sh
├── isnap-list.sh
├── isnap-restore.sh
├── snapconfig.json
└── isnap-create.sh
``` 

The script files (`*.sh`) are further described in sectio [Workflows and scripts](#Workflows-and-scripts). The configuration file (`snapconfig.json`) is described in the next section [Adjust configuration files](#Adjust-configuration-files).


### Adjust configuration file

For each Storage Protect instance a list of configuration parameters is required. The instance is identified by its instance username. This instance name is unique in a cluster and is mapped to the following configuration parameters in a configuration file:

| Parameter | Description | Required | Example |
|-----------|-------------|---------|---------|
| instName | Instance name, corresponds to the instance user | yes | tsminst1 |
| instUser | Instance user, used for Db operation | no | tsminst1 |
| snapPrefix | Name prefix of the snapshot, used to create and restore snapshot	| yes | tsminst1-snap |
| dirsToSnap | file system name and fileset name, used to create and restore snapshot. If fileset name is not given, global snapshot are used. | yes |	fsname+fsetname  |
| dbName | Name of the Db2, usually this is TSMDB1 | yes | TSMDB1 | 
| snapRetention | Retention time in days for the snapshot, default is 0 days. Snapshots cannot be deleted during retention time	| no | 5 |
| serverInstDir | Instance directory of the server (where dsmserv.opt resides). Must only be specified if different to instance user home. Default is instance user home directory.	| no | /tsminst/inst01/home |
| apiServerIP | IP address or host name of the REST API server. If this parameter is set, then the REST API is used instead of the CLI. | no | x.x.x.x |
| apiServerPort | IP port of the REST API server. If not set it defaults to 443 | yes | 443 |
| apiCredentials | REST API user and password encoded in base64 as User:Password  | yes | YWRtaW46VGVzdDEyMzRhIQ== |

When the parameter `apiServer` along with the `apiCredentials` are defined in the configuration file, then the Storage Scale REST API is used instead of the command line. 

The configuration parameter for each instance is stored in a configuration file: `snapconfig.json`. Here is an example for the configuration file for two instances (tsminst1 and tsminst2). Note the concatination of filesystem and fileset names using the `+` character'

```
[
  {
	"instName": "tsminst1",
	"dbName": "TSMDB1",
	"snapPrefix": "tsminst1-snap",
	"snapRetention": "4",
  "serverInstDir": "/tsminst/inst01/home",
	"apiServerIP": "REST API server IP",
	"apiServerPort": "REST API server IP, default is 443",
	"apiCredentials": "base64 encoded API user User:Password",
	"dirsToSnap": ["tsmdb+inst01", "tsmlog+inst01", "tsmalog+inst01", "tsmstg+inst01", "tsminst+inst01", "tsmbackup+inst01"]
  },
  {
	"instName": "tsminst2",
	"dbName": "TSMDB1",
	"snapPrefix": "tsminst2-snap",
	"snapRetention": "4",
  "serverInstDir": "/tsminst/inst02/home",
	"apiServerIP": "REST API server IP",
	"apiServerPort": "REST API server IP, default is 443",
	"apiCredentials": "base64 encoded API user UserPassword",
	"dirsToSnap": ["tsmdb+inst02", "tsmlog+inst02", "tsmalog+inst02", "tsmstg+inst02", "tsminst+inst02", "tsmbackup+inst02"]
  }
]
``` 

The exact location of the configuration file must be updated in the scripts itself. The default location is `/usr/local/bin`.   


### REST API 

When the parameter `apiServer` along with the `apiCredentials` are defined in the configuration file (see, [Adjust configuration files](#Adjust-configuration-files)), then the Storage Scale REST API is used instead of the command line. Using the Storage Scale REST API to manage consistent immutable snapshots requires an API user with the role snapAdmin to be created. This can be done via the Storage Scale GUI under Services - GUI - Users, or via the command line on the GUI node(s). The following command creates a user `snapadmin` with the role `SnapAdmin`:

```
/usr/lpp/mmfs/gui/cli/mkuser snapadmin -p <password> -g SnapAdmin
```

To use the API user credentials, the username and password must be base64 encoded. The following command encodes the username `user` and password `secret` in base64, the resulting string can be used as value for the parameter `apiCredentials` in the configuration file:

```
echo -n user:secret | base64
dXNlcjpzZWNyZXQ=
```

It is recommended to test the API connection from the servers where the scripts are installed. The following example gets the cluster configuration using the REST API. The base64 encoded credential is following the string `Authorization: Basic`:

```
curl -k -X GET --header 'Accept: application/json' --header 'Authorization: Basic dXNlcjpzZWNyZXQ=' 'https://GUI-Server:GUI-Port/scalemgmt/v2/cluster'
```

When using the REST API, there are some limitations:

- The `isnap-restore.sh` scripts does not perform the snapshot restore, because there is no API endpoint for this. Instead the script provides detailed instructions for performing the restore manually
- When listing snapshots using `isnap-list.sh` right after deleting snapshots, then the deleted snapshots may still be shown temporarily. In this case list the snapshots again. 


### Sudo configuration

To create consistent snapshots for a Storage Protect instance via command line, the Storage Protect Db2 of the instance must be suspended. For the restoration of snapshots the instance Db2 must be restarted and resumed. These steps require authorization to perform Db2 commands. By default, the instance user is authorized to connect to the instance Db2 and perform Db2 commands. Therefore, the instance user can create the snapshots for its instance. To do this, the instance user must be allowed to create snapshots in Storage Scale. 

Sudo configuration is only required when the Storage Scale CLI is used. It enables the instance user to manage Storage Scale snapshots. 

If the snapshots are managed via the CLI, then the instance user can be configured with privileges to create and restore snapshots. This can be done leveraging a sudo configuration. Find below the adjustments that should be done to the sudo configuration:

``` 
### add /usr/lpp/mmfs/bin to secure_path
Defaults    secure_path = /sbin:/bin:/usr/sbin:/usr/bin:/usr/lpp/mmfs/bin

### Allow a specifig instance user to run snapshot commands and mmsysmonc without password
tsminst1 ALL=(ALL)       NOPASSWD: /usr/lpp/mmfs/bin/mmcrsnapshot,/usr/lpp/mmfs/bin/mmlssnapshot,/usr/lpp/mmfs/bin/mmdelsnapshot,/usr/lpp/mmfs/bin/mmrestorefs,/usr/lpp/mmfs/bin/mmsysmonc,/usr/lpp/mmfs/bin/mmlsfileset,/usr/bin/du

### Alternatively allow all users in group tsmsrvrs to run snapshot commands and mmsysmonc without password
%tsmsrvrs ALL=(ALL)       NOPASSWD: /usr/lpp/mmfs/bin/mmcrsnapshot,/usr/lpp/mmfs/bin/mmlssnapshot,/usr/lpp/mmfs/bin/mmdelsnapshot,/usr/lpp/mmfs/bin/mmrestorefs,/usr/lpp/mmfs/bin/mmsysmonc,/usr/lpp/mmfs/bin/mmlsfileset
``` 

**Note:** to raise events if the snapshot creation fails, the `mmsysmonc` command must also be allowed in the sudo context (see [Event notification](#Event-notification). 

If a different command than `/usr/bin/sudo` is used for privilege escalation, then the variable `sudoCmd` can be adjusted and set to the command that is used. By default the variable `sudoCmd` is set to `/usr/bin/sudo` in all isnap-scripts. 

If the snapshots are managed via the REST API, then the instance user does not need the sudo-privileges for the CLI based snapshot commands. 


### Event notification

When SGC creation fails (see section [Create safeguarded copy](#Creating-safeguarded-copy)) then an event can be raised with the Storage Scale system health monitoring. This event is visible in the GUI and can be forwarded to the datacenter monitoring infrastructure via SNMP, email or webhooks. 

Storage Scale allows [creating and raising custom events](https://www.ibm.com/docs/en/storage-scale/5.1.7?topic=health-creating-raising-finding-custom-defined-events). This is based on event definitions in JSON format in file `custom.json`. Find below the events defined in `custom.json`:

```
{
"snap_warn":{
       "cause":"Creating consistent snapshots ended with warnings.",
        "user_action":"Investigate the error message and logs.",
        "scope":"NODE",
        "code":"cu_1803",
        "description":"Creating snapshots using the isnap-create script ended with warnings.",
        "event_type":"INFO",
        "message":"Warning creating snapshot for instance {0}. Message: {1}",
        "severity":"WARNING"
 },
"snap_fail":{
       "cause":"Creating consistent snapshots ended with errors. ",
        "user_action":"Investigate the error message and logs.",
        "scope":"NODE",
        "code":"cu_1804",
        "description":"Creating snapshot using the isnap-create script ended with errors. Investigate the error message and logs.",
        "event_type":"INFO",
        "message":"Error creating snapshot for instance {0}. Message: {1}",
        "severity":"ERROR"
 },
"delsnap_fail":{
       "cause":"Deleting snapshot(s) failed.",
        "user_action":"Investigate the error message and logs.",
        "scope":"NODE",
        "code":"cu_1805",
        "description":"Deleting snapshot using the isnap-del script ended with errors. Investigate the error message and logs.",
        "event_type":"INFO",
        "message":"Error deleting snapshot for instance {0}. Message: {1}",
        "severity":"ERROR"
 }
}
```


Once the custom events are installed, test if the events are working:

```
mmhealth event show snap_fail
mmhealth event show snap_warn
mmhealth event show delsnap_fail
```

The scripts `isnap-create.sh` and `isnap-del.sh` raise custom events using the Storage Scale command `mmsysmonc`. This requires the instance user to have privileges to run the `mmsysmonc` command (see [Sudo configuration](#Sudo-configuration)). By default, the command to raise events (`mmsysmonc`) is commented out in the scripts. 


### Test scripts

To test scripts change to the instance user (for example `tsminst1`) and test the scripts:

```
# su - tsminst1
$ isnap-list.sh
$ isnap-create.sh --help
$ isnap-restore.sh --help
```

### Create schedules

The creation of consistent SGC can be scheduled using `cron`. The creation of SGC must be executed by the instance user (for example `tsminst1`), hence the schedule must be created in the context of the instance user. 

**Note:** Do not schedule the SGC creation at the same time when a Storage Protect Db backup is executed or during heavy backup or housekeeping workloads!!

The example below creates an SGC every day at midnight using `isnap-create.sh`. It requires to enter the `home-directory-of-instance-user` for parameters `HOME` and `BASH_ENV`:


```
# su - tsminst1
$ crontab -e

SHELL=/bin/bash
HOME=[/home-directory-of-instance-user]
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
BASH_ENV=[/home-directory-of-instance-user].profile
MAILTO=root

# create snapshot at midnight every day
00 00 *  *  * /usr/local/bin/isnap-create.sh -r >> /tmp/snaplogs/tsminst1-snapcreate.log 2>&1
```

An alternative way to schedule the creation of SGC - e.g. for AIX - is to source the `profile` of the instance user prior to executing `isnap-create.sh`:

```
# create snapshot at midnight every day
00 00 *  *  * source [/home-directory-of-instance-user].profile; /usr/local/bin/isnap-create.sh -r >> /tmp/snaplogs/tsminst1-snapcreate.log 2>&1
```


SGC that are expired based on the snapshot retention time can be deleted. The snapshot retention time is configured in the configuration file as parameter `snapRetention` (see [Adjust configuration files](#Adjust-configuration-files)). To accommodate the automated deletion of SGC that are older than the retention time, the script `isnap-del.sh` is used. The example below deletes SGC that are older than 10 days. 

```
# delete snapshots older than 10 days at 00:00
15 00 * * * /usr/local/bin/isnap-del.sh -i tsminst1 -g 10 >> /tmp/snapdel/tsminst1-snapdel.log 2>&1
```

**Note:** the age of the snapshot given with the parameter `-g` must be equal or greater than the snapshot retention time given in configuration parameter `snapRetention`. 


------------------------------

## Workflows and scripts

This section describes the workflows and scripts implementing these workflows. All scripts require a valid configuration file `snapconfig.json`, see section [Adjust configuration files](#Adjust-configuration-files) for more details. 

The default location of the configuration file `snapconfig.json` is in `/usr/local/bin`. If the configuration file is stored in a different directory, then the script variable `configFile=` must be manually adjusted in all scripts. 


### Create safeguarded copy

Safeguarded copies are created using the script [isnap-create.sh](isnap-create.sh). This script must be run in the environmental context of the instance user, because it requires interactions with the Storage Protect database. 

The creation of safeguarded copies runs in three phases:

- **Phase 1:** Check configuration parameter and that Storage Protect instance is running, connect to the instance Db2 and write suspend the Db2. 
- **Phase 2:** Freeze file systems, create SGC for all relevant filesets using the `mmcrsnapshot` command.
- **Phase 3:** Unfreeze file sysetms and resume the Db2 of the instances. 


The `isnap-create.sh` script requires the configuration file `snapconfig.json` to be stored in directory `/usr/local/bin`. 

The Storage Protect instance must be running. 

If the configuration parameter `apiServerIP` is specified, then the Storage Scale REST API is used. 

**Syntax:**

```
isnap-create.sh -r | --run 
	-r | --run: performs the workflow to create consistent snapshots (required)
```


This script creates SGC for all relevant filesets defined as parameter `dirsToSnap` in the configuration file `snapconfig.json`. The name of the SGC created at a given point in time is composed from the `snapPrefix` parameter and the current time stamp. The retention time configured in parameter `snapRetention` is applied for all SGC.

If the Storage Protect server instance is not running, or the script is executed on a node where the Storage Protect instance does not run, then no safeguarded copy is created. 

The scripts writes runtime information to standard out. 


### Restore safeguarded copy

Safeguarded copies are restored using the script [isnap-restore.sh](isnap-restore.sh). This script must be run in the environmental context of the instance user, because it requires interactions with the Storage Protect database. 

The restoration of safeguarded copies runs in three phases:

- **Phase 1:** Check that the instance is down, restore the SGC for all relevant Storage Scale filesets using the `mmrestorefs` command.
- **Phase 2:** Restart the instance Db2 and resume the instance Db2.  
- **Phase 3:** Start the Storage Protect instance in foreground and in maintenance mode.


If the server instance directory is different than the instance user home directory, then the variable `serverInstDir` must be set to the server instance directory path. Otherwise, starting the Storage Protect instance in maintenance mode does not work. The variable `serverInstDir` can be directly adjusted in the `isnap-restore.sh` script. 

If the configuration parameter `apiServerIP` is specified, then the snapshots are not restored automatically because there is no REST API endpoint to restore snapshots. Instead the script checks some pre-requisites and prints instructions to perform the snapshot restore and starting the instance.

The Storage Scale REST API user must have the role `snapshot administrator`. 

The `isnap-restore.sh` script requires the configuration file `snapconfig.json` to be stored in directory `/usr/local/bin`. 

The Storage Protect instance must not be running. 


**Syntax:**

```
isnap-restore.sh snapshot-name | -h | --help
	snapshot-name: specifies the name of the snapshot to be restored. 
	-h | --help:   show the syntax
```

The script does not perform the restore under the following conditions

- Configuration parameters in the configuration are not valid
- Storage Protect instance is still running on the server
- Storage Scale REST API does not have the role `Snapshot Administrator`
- Snapshot to be restored does not exist on all filesets


**Note:** If there are nested independent filesets within the independent fileset to be snapped, then these nested independent are not included in the snapshot. Therefore, it is not supported to use nested independent fileset. 

**Note:** If there are nested dependent filesets within the independent fileset to be snapped, then these nested dependent dependent are not restored. The files of the dependent fileset are included in the snapshot and can be restored manually by copying the files from the snapshot into the dependent fileset directory. Therefore, it is not recommended to use nested dependent filesets.  

**Note:** If quota is enabled on file systems and filesets, then the snapshot restore may fail. Disable quota prior to restore and enable quota after the snapshot restore. Alternatively, unmount the file system and perform the snapshot restore. 

**Note:** The script must be exectured as instance user on the server where the instance was running. The script requires that the instance is stopped. When running the script on one server while the instance is running on another server, the script does not detect this and performs the restore operation while the instance may be running on another server. This will cause the instance to become unavailable and potentially corrupted.



### List safeguarded copy

Safeguarded copies are listed by Storage Protect instance using the script [isnap-list.sh](fsnap-list.sh). The script can be executed by any user who has permissions to execute it. When not executed by the instance user, then the command line parameter `-i instance-name` must be provided. 

The script uses the command `mmlssnapshot`. If the configuration parameter `apiServerIP` is specified, then the Storage Scale REST API is used. 

The `isnap-list.sh` script requires the configuration file `snapconfig.json` to be stored in directory `/usr/local/bin`. 


**Syntax:**

```
isnap-list.sh [-i instance-user-name -s snapshot-name -v -h | --help]
	-i instance-user-name: 	Name of the instance (user) for which the snapshots are listed (optional, default is user running this command).
	-s snapshot-name:      	Snapshot name to be listed (checked) for all relevant file systems and filesets (optional, lists all snapshot by default).
	-v:                    	Show allocated blocks (optional, does not work with REST API)
	-h | --help:			Show this help message (optional).
```

The script iterates through all relevant file systems and filesets and list the snapshots on standard out. Here is an example:

The script iterates through the list of file system and filesets and lists the snapshots. Here is an example:

```
Snapshots in file system tsmdb: [data and metadata]
Directory                SnapId    Status  Created                   ExpirationTime            Fileset           Data  Metadata
tsminst2-20241105050005  663       Valid   Tue Nov  5 05:00:43 2024  Thu Nov  7 05:00:05 2024  srv02           1.465G    7.547M
tsminst2-20241106050005  664       Valid   Wed Nov  6 05:00:43 2024  Fri Nov  8 05:00:05 2024  srv02           1.483G    7.547M

Snapshots in file system tsmlog: [data and metadata]
Directory                SnapId    Status  Created                   ExpirationTime            Fileset           Data  Metadata
tsminst2-20241105050005  662       Valid   Tue Nov  5 05:00:44 2024  Thu Nov  7 05:00:05 2024  srv02           6.504G     6.75M
tsminst2-20241106050005  663       Valid   Wed Nov  6 05:00:43 2024  Fri Nov  8 05:00:05 2024  srv02            5.58G    6.688M

Snapshots in file system tsmalog: [data and metadata]
Directory                SnapId    Status  Created                   ExpirationTime            Fileset           Data  Metadata
tsminst2-20241105050005  662       Valid   Tue Nov  5 05:00:37 2024  Thu Nov  7 05:00:05 2024  srv02           2.902G     3.25M
tsminst2-20241106050005  663       Valid   Wed Nov  6 05:00:37 2024  Fri Nov  8 05:00:05 2024  srv02           2.877G     3.25M

Snapshots in file system tsmstg: [data and metadata]
Directory                SnapId    Status  Created                   ExpirationTime            Fileset           Data  Metadata
tsminst2-20241105050005  662       Valid   Tue Nov  5 05:00:38 2024  Thu Nov  7 05:00:05 2024  srv02           32.31G    20.53M
tsminst2-20241106050005  663       Valid   Wed Nov  6 05:00:38 2024  Fri Nov  8 05:00:05 2024  srv02           32.28G    20.31M

Snapshots in file system tsminst: [data and metadata]
Directory                SnapId    Status  Created                   ExpirationTime            Fileset           Data  Metadata
tsminst2-20241105050005  662       Valid   Tue Nov  5 05:00:39 2024  Thu Nov  7 05:00:05 2024  srv02           39.34M    17.28M
tsminst2-20241106050005  663       Valid   Wed Nov  6 05:00:38 2024  Fri Nov  8 05:00:05 2024  srv02           29.39M    17.28M

Snapshots in file system tsmbackup: [data and metadata]
Directory                SnapId    Status  Created                   ExpirationTime            Fileset           Data  Metadata
tsminst2-20241105050005  671       Valid   Tue Nov  5 05:00:46 2024  Thu Nov  7 05:00:05 2024  srv02           7.221G     5.25M
tsminst2-20241106050005  672       Valid   Wed Nov  6 05:00:45 2024  Fri Nov  8 05:00:05 2024  srv02           7.112G     5.25M

```

**Note:** Parameter `-s snapshot-name` can be used to check if a particular snapshot exists on all file systems and filesets. 


### Delete safeguarded copy

Safeguarded copies can be deleted for a Storage Protect instance using the script [isnap-del.sh](isnap-del.sh). The script can be executed by any user who has permissions to execute it. When not executed by the instance user, then the command line parameter `-i instance-name` must be provided. 
**Notes:** Safeguarded copies cannot be deleted unless they are expired. 

The script uses the command `mmdelsnapshot`. If the configuration parameter `apiServerIP` is specified, then the Storage Scale REST API is used. 

The `fsnap-del.sh` script requires the configuration file `snapconfig.json` to be stored in directory `/usr/local/bin`. 

**Syntax:**

```
isnap-del.sh -s snapshot-name | -g snapshot-age [-i instance-user-name -p]
  -s snapshot-name:      Name of the snapshot to be deleted from all file systems (mutually exclusive with option -g)
  -g snapshot-age:       Age of snapshots in days to be deleted from all file systems (mutually exclusive with option -s)
  -i instance-user-name: Instance user name, default is the user running this script. 
  -p:                    Preview snapshot names to be deleted from all file systems (optional). Does not deleted snapshots, just lists the snapshots to be deleted. 
```

The snapshot(s) to be deleted can either be specified with the snapshot name (parameter `-s snap-name`) or with the age of the snapshot in days (parameter `-g snap-age`). When specifying snapshot age, then all snapshots are deleted that are older than `snap-age` days relative to the date and time when the script is executed. The date and time in (hh:mm:ss) is taken into account. 

Preview mode (parameter `-p`) allows to preview the snapshots that would be deleted, but does not actually delete snapshots. 

The scripts writes runtime information to standard out. 


### Filesystem statistics

File system usage information can be displayed using the script [isnap-fscap.sh](isnap-fscap.sh). The script can be executed by any user who has permissions to execute it. When not executed by the instance user, then the command line parameter `-i instance-name` must be provided. 

The `isnap-fscap.sh` script requires the configuration file `snapconfig.json` to be stored in directory `/usr/local/bin`. 


**Syntax:**

```
Syntax: isnap-fscap.sh [-i instance-user-name]
  -i instance-user-name: instanz name to the fileset capacities
```

The script iterates through all relevant file systems and list the file system usage information. Here is an example:

```
Capacity usage for filesystem tsmdb, fileset srv02
7.4G    /gpfs/tsmdb/srv02/.snapshots
22G     /gpfs/tsmdb/srv02/
---------------------------------------------------
Capacity usage for filesystem tsmlog, fileset srv02
32G     /gpfs/tsmlog/srv02/.snapshots
160G    /gpfs/tsmlog/srv02/
---------------------------------------------------
Capacity usage for filesystem tsmalog, fileset srv02
15G     /gpfs/tsmalog/srv02/.snapshots
17G     /gpfs/tsmalog/srv02/
---------------------------------------------------
Capacity usage for filesystem tsmstg, fileset srv02
162G    /gpfs/tsmstg/srv02/.snapshots
2.2T    /gpfs/tsmstg/srv02/
---------------------------------------------------
Capacity usage for filesystem tsminst, fileset srv02
201M    /gpfs/tsminst/srv02/.snapshots
18G     /gpfs/tsminst/srv02/
---------------------------------------------------
Capacity usage for filesystem tsmbackup, fileset srv02
36G     /gpfs/tsmbackup/srv02/.snapshots
72G     /gpfs/tsmbackup/srv02/
---------------------------------------------------
Getting global file system statistic
Filesystem             Size  Used Avail Use% Mounted on
tsmdb                  600G   32G  569G   6% /gpfs/tsmdb
tsminst                 40G   20G   21G  49% /gpfs/tsminst
tsmlog                 500G  194G  307G  39% /gpfs/tsmlog
tsmstg                  10T  2.2T  7.9T  22% /gpfs/tsmstg
tsmalog                400G   22G  379G   6% /gpfs/tsmalog
tsmbackup              2.0T  135G  1.9T   7% /gpfs/tsmbackup
```

The first portion of the output shows the total allocation in the fileset and the capacity allocated by snapshots. The second portions shows the filel system usage statistic. 

Note, the scipt uses the configuration file (see [Adjust configuration files](#Adjust-configuration-files)) to determine file system and fileset combination of the instance. When running this script as non-instance user, then specify the instance user name with the parameter `-i instance-user`.
 


END OF DOCUMENT
