## Appendix D. Using predefined client schedules

The Blueprint configuration script creates several client schedules during server configuration. To use these schedules, you must complete configuration steps on the client system.

Table 33 lists the predefined schedules that are created on the server. The schedule names and descriptions are based on the default backup schedule start time of 10 PM. If you changed this start time during server configuration, the predefined client schedules on your system are named according to that start time. Information about updating client schedules to use with the IBM Storage Protect server is provided in the sections that follow the table.

For complete information about scheduling client backup operations, see your client documentation.

_Table 33. Predefined client schedules_

| Client | Schedule name | Schedule description |
|--------|---------------|----------------------|
| IBM Storage Protect for Databases: Data Protection for Oracle | ORACLE_DAILYFULL_10PM | Oracle Daily FULL backup that starts at 10 PM |
| IBM Storage Protect for Databases: Data Protection for Microsoft SQL Server | SQL_DAILYFULL_10PM | Microsoft SQL Daily FULL backup that starts at 10 PM |
| IBM Storage Protect backup-archive client | FILE_INCRFOREVER_10PM | File incremental-forever backup that starts at 10 PM |
| IBM Storage Protect for Mail: Data Protection for HCL Domino® | DOMINO_DAILYFULL_10PM | Daily FULL backup that starts at 10 PM |
| IBM Storage Protect for Mail:Data Protection for Microsoft Exchange Server | EXCHANGE_DAILYFULL_10PM | FULL backup that starts at 10 PM |
| IBM Storage Protect for Virtual Environments: Data Protection for Microsoft Hyper-V | HYPERV_FULL_10PM | Hyper-V full backup that starts at 10 PM |

### Data Protection for Oracle 

Data Protection for Oracle does not include a sample backup file. You can create a script or .bat command file and update the **OBJECTS** parameter for the predefined schedule by using the **UPDATE SCHEDULE** server command. Specify the full path to the command file on the client system unless you save the command file in the client installation directory. Then, you must provide only the file name. For example, to update the ORACLE_DAILYFULL_10PM schedule that is in the DATABASE domain, issue the following command. Specify the name of the command file that you want to use in the client installation directory. In this example, the command file is named schedcmdfile.bat.
```
update schedule database oracle_dailyfull_10pm obj=schedcmdfile.bat
```

### Data Protection for Microsoft SQL Server
The sample schedule file that is included with Data Protection for Microsoft SQL Server is named sqlfull.cmd. This file can be customized for use with IBM Storage Protect server. If you save the file to the client installation directory on the client system, you do not have to update the predefined schedule to include the full path to the file.

### Backup-archive client
When you use the predefined schedule for backup-archive clients, the server processes objects as they are defined in the client options file, unless you specify a file to run a command or macro. For information about setting the domain, include, and exclude options for backup operations, see the online product documentation:

* [Client options reference (V7.1)](https://www.ibm.com/docs/en/tsm/7.1.6?topic=clients-backup-archive-client-options-commands)
* [Client options reference (V8.1)](https://www.ibm.com/docs/en/spectrum-protect/8.1.0?topic=clients-backup-archive-client-options-commands)

### Data Protection for HCL Domino
The sample schedule file that is included with Data Protection for HCL Domino is named domsel.cmd. This file can be customized for use with IBM Storage Protect server. If you save the file to the client installation directory on the client system, you do not have to update the predefined schedule to include the full path to the file.

### Data Protection for Microsoft Exchange Server
The sample schedule file that is included with Data Protection for Microsoft Exchange Server is named `excfull.cmd`. This file can be customized for use with IBM Storage Protect server. If you save the file to the client installation directory on the client system, you do not have to update the predefined schedule to include the full path to the file.

### Data Protection for Microsoft Hyper-V
No sample schedule file is provided with Data Protection for Microsoft Hyper-V. To create a .cmd file that can back up multiple virtual machines, complete the following steps:

1. Update the client options file to include the following settings:
   ```
    commmethod          tcpip
    tcpport             1500
    TCPServeraddress    <IBM Storage Protect server name>
    nodename            <node name>
    passwordaccess      generate
    vmbackuptype        hypervfull
   ```
1. For each virtual machine that you want to back up, create a separate script file. A unique file is needed to ensure that a log is saved for each backup. For example, create a file that is named hvvm1.cmd. Include the backup command, the name of the virtual machine, the client options file, and the log file that you want to create on the first line. On the second line, include the word exit. </br>
   For example:
   ```
    dsmc backup vm "tsmhyp1vm3" -optfile=dsm-hv.opt >> hv_backup_3.log
    exit
   ```
   Repeat this step for each virtual machine that you want to back up.
1. Create a backup schedule file, for example, hv_backup.cmd.
1. Add an entry to hv_backup.cmd for each virtual machine script file that you created. </br>For example:
   ```
    start hvvm1.cmd
    choice /T 10 /C X /D X /N > NUL
    start hvvm2.cmd
    choice /T 10 /C X /D X /N > NUL
    start hvvm3.cmd
    choice /T 10 /C X /D X /N > NUL
    hvvm4.cmd
   ```
1. Issue the UPDATE SCHEDULE server command to update the predefined HYPERV_FULL_10PM schedule. Specify the full path for the Hyper-V backup schedule file location in the OBJECTS parameter.

