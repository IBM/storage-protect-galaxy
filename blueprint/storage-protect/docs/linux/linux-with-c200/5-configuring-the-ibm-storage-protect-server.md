## Chapter 5. Configuring the IBM Storage Protect server

Run the Blueprint configuration script, `sp_config.pl`, to configure the IBM Storage Protect server.

**Before you begin**

You can run the Blueprint configuration script in interactive or non mode. In interactive mode, you provide responses for each step in the script and accept defaults or enter values for the configuration. In noninteractive mode, the script uses a response file that contains answers to the script prompts.

To run the script in noninteractive mode, use one of the response files that are included in the blueprint
configuration compressed file. For instructions about how to use a response file, see Appendix C, ["Using a response file with the Blueprint configuration script"](appendix-c-using-a-response-file-with-the-blueprint-configuration-script.md).

**About this task**

When you start the script and select the size of the server that you want to configure, the script verifies the following hardware and system configuration prerequisites:

* Sufficient memory is available for server operations.
* Processor core count meets blueprint specifications.
* Kernel parameters are set correctly. If the values are not set as specified, they are automatically updated when you run the Blueprint configuration script to configure the server. For more information about kernel parameter settings, see Table 20.
* All required file systems are created.
* The minimum number of file system types exist and the minimum level of free space is available in each file system.

If all prerequisites checks are passed, the script begins server configuration. The following tasks are completed to configure the server for optimal performance, based on the scale size that you select:
* A Db2 database instance is created.
* The dsmserv.opt options file with optimum values is created.
* The server database is formatted.
* The system configuration is updated to automatically start the server when the system starts.
* Definitions that are required for database backup operations are created.
* A directory-container storage pool with optimal performance settings for data deduplication is defined. </br>You can use the `-legacy` option with the blueprint configuration script to force the creation of a deduplicated storage pool, which uses a FILE device class.
* Policy domains for each type of client workload are defined.
* Schedules for client backup are created.
* Server maintenance schedules that are sequenced for optimal data deduplication scalability are created.
* The client options file is created.

The blueprint configuration script includes a compression option that enables compression for both the archive log and database backups. You can save significant storage space by using this option, but the amount of time that is needed to complete database backups increases. The preferred method is to enable the option if you are configuring a small blueprint system because limited space is configured for the archive log and database backups.

The default setting for the `compression` option is disabled.

**Tip**: Do not confuse the blueprint configuration script compression option with inline compression of data in container storage pools, which is enabled by default with IBM Storage Protect V7.1.5 and later. 

Complete the following steps as the root user to run the Blueprint configuration script.

**Procedure**

1. Open a terminal window.
1. If you did not extract the Blueprint configuration script compressed file to prepare file systems for IBM Storage Protect, follow the instructions in ["Configure a file system by using the script"](4.4.1-configure-a-file-system-by-using-the-script.md).
1. Change to the `sp-config` directory by issuing the following command:
   ```
    cd sp-config
   ```
1. Run the configuration script in one of the following modes:
   * To run the configuration script in interactive mode and enter your responses at the script prompts, issue the following command:
     ```
     perl sp_config.pl
     ```
     Depending on how you preconfigured the system, you can accept the default values that are presented by the script. Use the information that you recorded in the ["Planning worksheets"](2.2-planning-worksheets.md). If you changed any of the default values during the preconfiguration step, you must manually enter your values at the script prompts.

   * To run the configuration script in noninteractive mode by using a response file to set configuration values, specify the response file when you run the script. For example:
      * To use the default response file for a medium system, issue the following command:
        ```
        perl sp_config.pl ./response-files/responsefilemed.txt
        ```
      If you encounter a problem during the configuration and want to pause temporarily, use the quit option. When you run the script again, it resumes at the point that you stopped. You can also open other terminal windows to correct any issues, and then return to and continue the script. When the script finishes successfully, a log file is created in the current directory.

1. Save the log file for future reference. </br>
   The log file is named `setupLog_<datestamp>.log` where `datestamp` is the date on which you ran the configuration script. If you run the script more than once on the same day, a version number is appended to the end of the name for each additional version that is saved. </br> For example, if you ran the script three times on July 27, 2013, the following logs are created:
   * setupLog_130727.log
   * setupLog_130727_1.log
   * setupLog_130727_2.log

**Results**

After the script finishes, the server is ready to use. Review Table 18 and the setup log file for details about your system configuration.

_Table 18. Summary of configured elements_

| Item  | Details  |
|-------|----------|
| Db2 database instance | <ul><li>The Db2 instance is created by using the instance user ID and instance home directory.</li><li>Db2 instance variables that are required by the server are set.</li><li>The Db2 `-locklist` parameter remains at the default setting of Automatic (for automatic management), which is preferred for container storage pools. If you are defining a non-container storage pool, you can use the `-locklist` parameter with the IBM Storage Protect blueprint configuration script, `sp_config.pl` , to revert to manually setting `-locklist` values.</li></ul> |
| Operating system user limits (ulimits) for the instance user | The following values are set: <ul><li>Maximum size of core files created (core): unlimited</li><li>Maximum size of a data segment for a process (data): unlimited</li><li>Maximum file size allowed (fsize): unlimited</li><li>Maximum number of open files that are allowed for a process (nofile): 65536</li><li>Maximum amount of processor time in seconds (cpu): unlimited</li><li>Maximum number of user processes (nproc): 16384</li></ul> |
| IBM Storage Protect API | <ul><li>An API dsm.sys file is created in the /opt/tivoli/tsm/server/bin/dbbkapi/ directory. The following parameters are set. Some values might vary, depending on selections that were made during the configuration:_</br>&emsp;servername TSMDBMGR_tsminst1</br>&emsp;tcpserveraddr localhost</br>&emsp;commmethod tcpip</br>&emsp;tcpserveraddr localhost</br>&emsp;tcpport 1500</br>&emsp;passworddir /home/tsminst1/tsminst1</br>&emsp;errorlogname /home/tsminst1/tsminst1/tsmdbmgr.log</br>&emsp;nodename \$\$TSMDBMGR\$\$_</li><li>The API password is set.</li></ul> |
| Server settings | <ul><li>The server is configured to start automatically when the system is started.</li><li>An initial system level administrator is registered.</li><li>The server name and password are set.</li><li>The following values are specified for SET commands:<ul><li>SET ACTLOGRETENTION is set to 180.</li><li>SET EVENTRETENTION is set to 180.</li><li>SET SUMMARYRETENTION is set to 180.</li></ul></li></ul> |
| IBM Storage Protect server options file | The dsmserv.opt file is set with optimal parameter values for server scale. The following server options are specified:<ul><li>ACTIVELOGSIZE is set according to scale size:<ul><li>Medium system: 131072</li></ul><li>If you enabled compression for the blueprint configuration, ARCHLOGCOMPRESS is set to Yes.</li><li>COMMTIMEOUT is set to 3600 seconds.</li><li>If you are using the -legacy option for data deduplication, DEDUPDELETIONTHREADS is set according to scale size:<ul><li>Medium system: 8</li></ul><li>DEDUPREQUIRESBACKUP is set to NO.</li><li>DEVCONFIG is specified as devconf.dat, which is where a backup copy of device configuration information will be stored.</li><li> EXPINTERVAL is set to 0 , so that expiration processing runs according to schedule.</li><li>IDLETIMEOUT is set to 60 minutes.</li><li>MAXSESSIONS is set according to scale size:<ul><li>Medium system: 500 maximum simultaneous client sessions</li></ul><li>The effective value for the SET MAXSCHEDSESSIONS option is 80% of the value that was specified for the MAXSESSIONS option:<ul><li>Medium system: 400 sessions</li></ul><li>NUMOPENVOLSALLOWED is set to 20 open volumes.</li><li>TCPWINDOWSIZE is set to 0</li><li>VOLUMEHISTORY is specified as volhist.dat, which is where the server will store a backup copy of volume history information. In addition to volhist.dat, which will be stored in the server instance directory, a second volume history option is specified to be stored in the first database backup directory for redundancy. |
| IBM Storage Protect server options file: database reorganization options |  Server options that are related to database reorganization are specified in the following sections.</br> Servers at V7.1.1 or later:<ul><li>ALLOWREORGINDEX is set to YES.</li><li>ALLOWREORGTABLE is set to YES.</li><li>DISABLEREORGINDEX is not set.</li><li>DISABLEREORGTABLE is set to _</br>&emsp;BF_AGGREGATED_BITFILES,BF_BITFILE_EXTENTS,</br>&emsp;ARCHIVE_OBJECTS,BACKUP_OBJECTS_</li><li>REORGBEGINTIME is set to 12:00.</li><li>REORGDURATION is set to 6.</li></ul> |
| Directory-container storage pool | A directory-container storage pool is created, and all of the storage pool file systems are defined as container directories for this storage pool. The following parameters are set in the DEFINE STGPOOL command:<ul><li>STGTYPE is set to DIRECTORY.</li><li>MAXWRITERS is set to NOLIMIT.</li></ul>For servers at V7.1.5 or later, compression is automatically enabled for the storage pool. |
| Storage pool if the -legacy option is specified | <ul><li>A FILE device class is created and tuned for configuration size:<ul><li>All storage pool file systems are listed with the DIRECTORY parameter in the DEFINE DEVCLASS command.</li><li>The MOUNTLIMIT parameter is set to 4000 for all size systems.</li><li>The MAXCAP parameter is set to 50 GB for all size systems.</li></ul><li>The storage pool is created with settings that are tuned for configuration size:</li><ul><li>Data deduplication is enabled.</li><li>The value of the IDENTIFYPROCESS parameter is set to 0 so that duplicate identification can be scheduled.</li><li>Threshold reclamation is disabled so that it can be scheduled.</li><li>The MAXSCRATCH parameter value is tuned based on the amount of storage that is available in the FILE storage pool.</li></ul></li></ul> |
| Server schedules | The following server maintenance schedules are defined:<ul><li> A replication storage rule is scheduled to run 10 hours after the start of the backup window. </br>The schedule is inactive by default. You must specify the parameter ACTIVE=Yes to enable the processing of the replication storage rule at the scheduled time. </br> **Remember**: If a replication storage rule is configured with the parameter ACTIONTYPE=NOREPLICATING , then you must define a replication subrule for the parent replication storage rule with the parameter ACTIONTYPE=REPLICATE to replicate data from specific nodes and filespace. </br>Sessions are based on system size:<ul><li>Medium system: 40</li></ul><li>Database backup is scheduled to run until it is complete. The schedule starts 14 hours after the beginning of the client backup window. </br> A device class that is named DBBACK_FILEDEV is created for the database backup. If the configuration script is started with the compression option, the BACKUP DB command runs with compress=yes.</br>The device class is created to allow a mount limit of 32. The file volume size is set to 50 GB. The device class directories include all of the database backup directories. The number of database backup sessions is based on the system size:<ul><li>Medium system: 4</li></ul>In addition, the SET DBRECOVERY command is issued. It specifies the device class, the number of streams, and the password for database backup operations. After a successful database backup operation, the DELETE VOLHISTORY command is used to delete backups that were created more than 4 days prior.</li><li> Expiration processing is scheduled to run until it is complete. The schedule starts 17 hours after the beginning of the client backup window. The RESOURCE parameter is set according to scale size and type of data deduplication storage pool:</br>Directory-container storage pools:<ul><li>Medium system: 30</li></ul>Non-container storage pools:<ul><li>Medium system: 8</li></ul></li></ul>If you are using the -legacy option for data deduplication, the following schedules are also defined:<ul><li>Duplicate identification is set for a duration of 12 hours. The schedule starts at the beginning of the client backup window. The NUMPROCESS parameter is set according to scale size:<ul><li>Medium system: 16</li></ul><li>Reclamation processing is set for a duration of 8 hours. The reclamation threshold is 25%.</br>The schedule starts 14 hours after the beginning of the client backup window. The RECLAIMPROCESS parameter is set as part of the storage pool definition, according to scale size:<ul><li>Medium system: 20</li></ul>|
| Policy domains | The following policy domains are created: <ul><li>STANDARD – The default policy domain</li><li>*server name*_DATABASE – Policy domain for database backups</li><li>*server name*_DB2 – Policy domain for Db2 database backups</li><li>*server name*_FILE – Policy domain for file backups that use the backup-archive client</li><li>*server name*_MAIL – Policy domain for mail application backups</li><li>*server name*_ORACLE – Policy domain for Oracle database backups</li><li>*server name*_VIRTUAL – Policy domain for virtual machine backups</li><li>*server name*_HANA – Policy domain for SAP HANA backups</li><li>*server name*_OBJECT - Policy domain for Amazon Simple Storage Service (S3) object data from IBM Storage Protect Plus offload operations</li></ul>Policy domains other than the STANDARD policy are named by using a default value with the server name. For example, if your server name is TSMSERVER1, the policy domain for database backups is TSMSERVER1_DATABASE. |
| Management classes | Management classes are created within the policy domains that are listed in the previous row. Retention periods are defined for 7, 30, 90, and 365 days. </br></br>The default management class uses the 30-day retention period.|
|Client schedules | Client schedules are created in each policy domain with the start time that is specified during configuration. </br>The type of backup schedule that is created is based on the type of client:<ul><li>File server schedules are set as incremental forever.</li><li>Data protection schedules are set as full daily.</li></ul>Some data protection schedules include command file names that are appropriate for the data protection client.</br>For more information about the schedules that are predefined during configuration, see [Appendix D, "Using predefined client schedules"](appendix-d-using-predefined-client-schedules.md).|

---
