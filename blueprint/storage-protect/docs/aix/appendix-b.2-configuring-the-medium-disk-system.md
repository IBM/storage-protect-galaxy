## Appendix B. Configuring the disk system by using commands

### Medium system

1. Connect to and log in to the disk system by issuing the `ssh` command. For example:
   ```
    ssh superuser@yourMediumStorageSystemHostname
   ```
1. <a name="medium-system-step-2"></a>Increase the memory that is available for the RAIDs to 125 MB by issuing the `chiogrp` command:
   ```
    chiogrp -feature raid -size 125 io_grp0
   ```
1. List drive IDs for each type of disk so that you can create the MDisk arrays in [Step "5"](#medium-system-step-5). Issue the `lsdrive` command. The output can vary, based on slot placement for the different disks. The output is similar to the following example:
   ```
    IBM_FlashSystem:tapv5kk:superuser>lsdrive
    id   status   use     tech_type          capacity    enclosure_id slot_id    drive_class_id
    0    online   member   tier_nearline     7.3TB       1           26          0
    1    online   member   tier_nearline     7.3TB       1           44          0
    2    online   member   tier_nearline     7.3TB       1           1           0
    3    online   member   tier_nearline     7.3TB       1           34          0
    4    online   member   tier_nearline     7.3TB       1           20          0
    5    online   member   tier_nearline     7.3TB       1           25          0
    < ... >
    91   online   member   tier_nearline     7.3TB       1           2           0
    92   online   member   tier1_flash       1.7TB       2           4           1
    93   online   member   tier1_flash       1.7TB       2           1           1
    94   online   member   tier1_flash       1.7TB       2           3           1
    95   online   member   tier1_flash       1.7TB       2           6           1
    96   online   member   tier1_flash       1.7TB       2           5           1
    97   online   member   tier1_flash       1.7TB       2           2           1
   ```
1. Create the MDisk groups for the IBM Storage Protect database and storage pool. Issue the `mkmdiskgroup` command for each pool, specifying 1024 for the extent size:
   ```
    mkmdiskgrp -name db_grp0 -ext 1024
    mkmdiskgrp -name stgpool_grp0 -ext 1024
   ```
1. <a name="medium-system-step-5"></a>Create MDisk arrays by using `mkdistributedarray` commands. Specify the commands to add the MDisk arrays to the data pools that you created in the previous step. </br> For example:
   ```
    mkdistributedarray -name db_array0 -level raid6 -driveclass 1 -drivecount 6 -stripewidth 5 -rebuildareas 1 -strip 256 db_grp0
    mkdistributedarray -name stgpool_array0 -level raid6 -driveclass 0 -drivecount 46 -stripewidth 12 -rebuildareas 2 -strip 256 stgpool_grp0
    mkdistributedarray -name stgpool_array1 -level raid6 -driveclass 0 -drivecount 46 -stripewidth 12 -rebuildareas 2 -strip 256 stgpool_grp0
   ```
1. <a name="medium-system-step-6"></a>Create the storage volumes for the system. Issue the `mkvdisk` command for each volume, specifying the volume sizes in MB. For example:
   ```
    mkvdisk -mdiskgrp db_grp0 -size 656999 -name db_00 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 656999 -name db_01 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 656999 -name db_02 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 656999 -name db_03 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 656999 -name db_04 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 656999 -name db_05 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 656999 -name db_06 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 656999 -name db_07 -iogrp 0 -nofmtdisk

    mkvdisk -mdiskgrp db_grp0 -size 150528 -name alog -iogrp 0 -nofmtdisk

    mkvdisk -mdiskgrp stgpool_grp0 -size 2097152 -name archlog -iogrp 0 -nofmtdisk

    mkvdisk -mdiskgrp stgpool_grp0 -size 15728640 -name backup_00 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 15728640 -name backup_01 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 15728640 -name backup_02 -iogrp 0 -nofmtdisk

    mkvdisk -mdiskgrp stgpool_grp0 -size 30648320 -unit mb -name filepool_00 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 30648320 -unit mb -name filepool_01 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 30648320 -unit mb -name filepool_02 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 30648320 -unit mb -name filepool_03 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 30648320 -unit mb -name filepool_04 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 30648320 -unit mb -name filepool_05 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 30648320 -unit mb -name filepool_06 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 30648320 -unit mb -name filepool_07 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 30648320 -unit mb -name filepool_08 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 30648320 -unit mb -name filepool_09 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 30648320 -unit mb -name filepool_10 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 30648320 -unit mb -name filepool_11 -iogrp 0 -nofmtdisk
   ```
1. Create a logical host object by using the mkhost command. Specify the Fibre Channel WWPNs from your operating system and specify the name of your host. To obtain the WWPNs from your system, follow the instructions in ["Step 1: Setup and configure hardware"](#step-1-setup-and-configure-hardware). </br> For example, to create a host that is named hostone with a list that contains FC WWPNs 10000090FA3D8F12 and 10000090FA49009E , issue the following command:
   ```
    mkhost -name hostone -fcwwpn 10000090FA3D8F12:10000090FA49009E -iogrp 0 -type=generic -force
   ```
1. Map the volumes that you created in [Step "6"](#medium-system-step-6) to the new host. Issue the mkvdiskhostmap command for each volume. For example, issue the following commands where hostname is the name of your host:
   ```
    mkvdiskhostmap -host hostname -scsi 0 db_00
    mkvdiskhostmap -host hostname -scsi 1 db_01
    mkvdiskhostmap -host hostname -scsi 2 db_02
    mkvdiskhostmap -host hostname -scsi 3 db_03
    mkvdiskhostmap -host hostname -scsi 4 db_04
    mkvdiskhostmap -host hostname -scsi 5 db_05
    mkvdiskhostmap -host hostname -scsi 6 db_06
    mkvdiskhostmap -host hostname -scsi 7 db_07

    mkvdiskhostmap -host hostname -scsi 8 alog

    mkvdiskhostmap -host hostname -scsi 9 archlog

    mkvdiskhostmap -host hostname -scsi 10 backup_00
    mkvdiskhostmap -host hostname -scsi 11 backup_01
    mkvdiskhostmap -host hostname -scsi 12 backup_02

    mkvdiskhostmap -host hostname -scsi 13 filepool_00
    mkvdiskhostmap -host hostname -scsi 14 filepool_01
    mkvdiskhostmap -host hostname -scsi 15 filepool_02
    mkvdiskhostmap -host hostname -scsi 16 filepool_03
    mkvdiskhostmap -host hostname -scsi 17 filepool_04
    mkvdiskhostmap -host hostname -scsi 18 filepool_05
    mkvdiskhostmap -host hostname -scsi 19 filepool_06
    mkvdiskhostmap -host hostname -scsi 20 filepool_07
    mkvdiskhostmap -host hostname -scsi 21 filepool_08
    mkvdiskhostmap -host hostname -scsi 22 filepool_09
    mkvdiskhostmap -host hostname -scsi 23 filepool_10
    mkvdiskhostmap -host hostname -scsi 24 filepool_11
   ```

