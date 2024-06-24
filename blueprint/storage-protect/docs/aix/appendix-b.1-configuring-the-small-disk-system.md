## Appendix B. Configuring the disk system by using commands

### Small system

1. Connect to and log in to the disk system by issuing the ssh command. For example:
   ```
   ssh superuser@yourSmallStorageSystemHostname
   ```
1. List drive IDs for each type of disk so that you can create the managed disk (MDisk) arrays in [Step "4"](#small-system-step-4). Issue the `lsdrive` command. The output can vary, based on slot placement for the different disks. The output is similar to the following example:
   ```
    id   status   use         tech_type      capacity    ...   enclosure_id   slot_id ...
    0    online   candidate   tier0_flash      1.7TB             1              3
    1    online   candidate   tier0_flash      1.7TB             1              4
    2    online   candidate   tier0_flash      1.7TB             1              1
    3    online   candidate   tier0_flash      1.7TB             1              2
    4    online   candidate   tier_enterprise  2.2TB             2              3
    5    online   candidate   tier_enterprise  2.2TB             2              6
    6    online   candidate   tier_enterprise  2.2TB             2              1
    7    online   candidate   tier_enterprise  2.2TB             2              7
    8    online   candidate   tier_enterprise  2.2TB             2              10
    9    online   candidate   tier_enterprise  2.2TB             2              5
    10   online   candidate   tier_enterprise  2.2TB             2              4
    11   online   candidate   tier_enterprise  2.2TB             2              2
    12   online   candidate   tier_enterprise  2.2TB             2              9
    13   online   candidate   tier_enterprise  2.2TB             2              11
    <...>
   ```
1. Create the MDisk groups for the IBM Storage Protect database and storage pool. Issue the `mkmdiskgroup` command for each pool, specifying 256 for the extent size:
   ```
    mkmdiskgrp -name db_grp0 -ext 256
    mkmdiskgrp -name stgpool_grp0 -ext 256
   ```
1. <a name="small-system-step-4"></a>Create MDisk arrays by using `mkdistributedarray` commands. Specify the commands to add the MDisk arrays to the data pools that you created in the previous step. For example:
   ```
    mkdistributedarray -name db_array0 -level raid5 -driveclass 2 -drivecount 4 -stripewidth 3 -rebuildareas 1 -strip 256 db_grp0
    mkdistributedarray -name stgpool_array0 -level raid6 -driveclass 1 -drivecount 44 -stripewidth 12 -rebuildareas 2 -strip 256 stgpool_grp0
   ```

1. <a name="small-system-step-5"></a>Create the storage volumes for the system. Issue the `mkvdisk` command for each volume, specifying the volume sizes in MB. For example:
   ```
    mkvdisk -mdiskgrp db_grp0 -size 343296 -name db_00 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 343296 -name db_01 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 343296 -name db_02 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 343296 -name db_03 -iogrp 0 -nofmtdisk

    mkvdisk -mdiskgrp db_grp0 -size 148736 -name alog -iogrp 0 -nofmtdisk

    mkvdisk -mdiskgrp stgpool_grp0 -size 1244928 -name archlog -iogrp 0 -nofmtdisk

    mkvdisk -mdiskgrp stgpool_grp0 -size 3303398 -unit mb -name backup_00 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 3303398 -unit mb -name backup_01 -iogrp 0 -nofmtdisk

    mkvdisk -mdiskgrp stgpool_grp0 -size 15859710 -unit mb -name filepool_00 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 15859710 -unit mb -name filepool_01 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 15859710 -unit mb -name filepool_02 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 15859710 -unit mb -name filepool_03 -iogrp 0 -nofmtdisk
   ```
1. Create a logical host object by using the mkhost command. Specify the Fibre Channel WWPNs from your operating system and specify the name of your host. To obtain the WWPNs from your system, follow the instructions in ["Step 1: Setup and configure hardware"](#step-1-setup-and-configure-hardware). </br>For example, to create a host that is named hostone with a list that contains FC WWPNs 10000090FA3D8F12 and 10000090FA49009E, issue the following command:
   ```
    mkhost -name hostone -fcwwpn 10000090FA3D8F12:10000090FA49009E -iogrp 0 -type=generic -force
   ```
1. Map the volumes that you created in [Step "5"](small-system-step-5) to the new host. Issue the `mkvdiskhostmap` command for each volume. For example, issue the following commands where _hostname_ is the name of your host:
   ```
    mkvdiskhostmap -host hostname -scsi 0 db_00
    mkvdiskhostmap -host hostname -scsi 1 db_01
    mkvdiskhostmap -host hostname -scsi 2 db_02
    mkvdiskhostmap -host hostname -scsi 3 db_03

    mkvdiskhostmap -host hostname -scsi 4 alog

    mkvdiskhostmap -host hostname -scsi 5 archlog

    mkvdiskhostmap -host hostname -scsi 6 backup_0
    mkvdiskhostmap -host hostname -scsi 7 backup_1

    mkvdiskhostmap -host hostname -scsi 8 filepool_00
    mkvdiskhostmap -host hostname -scsi 9 filepool_01
    mkvdiskhostmap -host hostname -scsi 10 filepool_02
    mkvdiskhostmap -host hostname -scsi 11 filepool_03
   ```

